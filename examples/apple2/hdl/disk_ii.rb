# frozen_string_literal: true

# Apple II Disk II Controller
# Based on Stephen A. Edwards' neoapple2 implementation
#
# Disk II emulator - read-only, feeds "pre-nibblized" data to processor
# Supports single-track buffer and one drive
#
# Memory Map (slot 6):
# C080-C087: Phase 0-3 Head Stepper Motor Control
# C088-C089: Motor On/Off
# C08A-C08B: Drive Select (1/2)
# C08C-C08D: Q6 (Shift/Load)
# C08E-C08F: Q7 (Write request)
#
# Q7 Q6 Mode
# 0  0  Read
# 0  1  Sense write protect
# 1  0  Write
# 1  1  Load Write Latch
#
# Track format: 0x1A00 bytes per track (6656 bytes)
# 35 tracks total = 227.5 KB per disk image

require 'rhdl/hdl'

module RHDL
  module Examples
    module Apple2
      # Disk II ROM (256 bytes boot ROM at $C600-$C6FF)
    # Pure DSL component - ROM data loaded via simulation helper or initial: parameter
    class DiskIIROM < RHDL::HDL::Component
      include RHDL::DSL::Memory

      input :clk
      input :addr, width: 8
      output :dout, width: 8

      # ROM initialized to zeros by default via DSL
      # For actual ROM data, use: memory :rom, depth: 256, width: 8, initial: ROM_DATA
      memory :rom, depth: 256, width: 8

      # Asynchronous read (combinational) - suitable for small ROM
      # For BRAM inference, use: sync_read :dout, from: :rom, clock: :clk, addr: :addr
      async_read :dout, from: :rom, addr: :addr

      # Simulation helper: load ROM data at runtime
      def load_rom(data)
        data.each_with_index do |byte, i|
          break if i >= 256
          mem_write(:rom, i, byte, 8)
        end
      end
    end

    # Main Disk II Controller
    class DiskII < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential
      include RHDL::DSL::Memory

      # Clock inputs
      input :clk_14m
      input :clk_2m
      input :pre_phase_zero

      # Bus interface
      input :io_select                   # C600-C6FF ROM access
      input :device_select               # C0E0-C0EF I/O access
      input :reset
      input :a, width: 16                # Address bus
      input :d_in, width: 8              # Data from CPU

      output :d_out, width: 8            # Data to CPU
      output :track, width: 6            # Current track (0-34)
      output :track_addr, width: 14      # Address within track buffer
      output :d1_active                  # Drive 1 motor on
      output :d2_active                  # Drive 2 motor on

      # Track RAM interface (for loading track data)
      input :ram_write_addr, width: 14
      input :ram_di, width: 8
      input :ram_we

      # Track buffer (pre-nibblized)
      # NOTE: The reference design uses a single-track RAM and an external loader.
      # We keep a flattened image here so native IR backends can bulk-load all
      # tracks once and still follow the same controller semantics.
      TRACK_SIZE = 6656
      TRACKS = 35
      memory :track_memory, depth: TRACK_SIZE * TRACKS, width: 8

      # Disk II ROM sub-component
      instance :rom, DiskIIROM

      # Connect ROM
      port :clk_14m => [:rom, :clk]
      wire :rom_addr, width: 8
      wire :rom_dout, width: 8
      port :rom_addr => [:rom, :addr]
      port [:rom, :dout] => :rom_dout

      # Internal registers (declared as wires for sequential block)
      wire :motor_phase, width: 4
      wire :drive_on
      wire :drive2_select
      wire :q6
      wire :q7
      wire :phase, width: 8
      wire :prev_clk_2m
      wire :prev_pre_phase_zero
      wire :prev_device_select
      wire :prev_a, width: 16
      wire :track_byte_addr, width: 15
      wire :byte_delay, width: 6

      # Single clocked process (clk_14m) with explicit clk_2m edge detect.
      # This keeps reference behavior while matching current DSL constraints.
      sequential clock: :clk_14m, reset: :reset, reset_values: {
        motor_phase: 0,
        drive_on: 0,
        drive2_select: 0,
        q6: 0,
        q7: 0,
        phase: 70,
        prev_clk_2m: 0,
        prev_pre_phase_zero: 0,
        prev_device_select: 0,
        prev_a: 0,
        track_byte_addr: 0,
        byte_delay: 0
      } do
        clk2m_rise = ~prev_clk_2m & clk_2m
        edge_pre_phase_zero = prev_pre_phase_zero
        edge_device_select = prev_device_select
        edge_a = prev_a

        prev_clk_2m <= clk_2m
        prev_pre_phase_zero <= pre_phase_zero
        prev_device_select <= device_select
        prev_a <= a

        # I/O register control (reference: sampled on CLK_2M rising edge).
        io_access = clk2m_rise & edge_pre_phase_zero & edge_device_select

        # Phase control (C080-C087)
        phase_access = io_access & ~edge_a[3]
        phase_bit = edge_a[2..1]
        phase_value = edge_a[0]

        motor_phase_next =
          (motor_phase & ~(lit(1, width: 4) << phase_bit)) |
          (mux(phase_value, lit(1, width: 4), lit(0, width: 4)) << phase_bit)

        motor_phase <= mux(phase_access, motor_phase_next, motor_phase)

        # Control registers (C088-C08F)
        ctrl_access = io_access & edge_a[3]
        ctrl_reg = edge_a[2..1]

        drive_on <= mux(ctrl_access & (ctrl_reg == lit(0, width: 2)),
          edge_a[0], drive_on
        )

        drive2_select <= mux(ctrl_access & (ctrl_reg == lit(1, width: 2)),
          edge_a[0], drive2_select
        )

        q6 <= mux(ctrl_access & (ctrl_reg == lit(2, width: 2)),
          edge_a[0], q6
        )

        q7 <= mux(ctrl_access & (ctrl_reg == lit(3, width: 2)),
          edge_a[0], q7
        )

        # Track byte address counter
        # Reference behavior:
        # - update on CLK_2M rising edge
        # - advance on C08C read during PRE_PHASE_ZERO OR when byte_delay wraps
        read_disk_edge = edge_device_select & (edge_a[3..0] == lit(0xC, width: 4))
        byte_delay_next = byte_delay - lit(1, width: 6)
        byte_tick = clk2m_rise
        advance = byte_tick & ((read_disk_edge & edge_pre_phase_zero) | (byte_delay_next == lit(0, width: 6)))
        track_byte_addr_next = mux(track_byte_addr == lit(0x33FE, width: 15),
          lit(0, width: 15),
          track_byte_addr + lit(1, width: 15)
        )
        byte_delay_tick = mux(byte_tick, byte_delay_next, byte_delay)

        track_byte_addr <= mux(advance, track_byte_addr_next, track_byte_addr)
        byte_delay <= mux(advance, lit(0, width: 6), byte_delay_tick)

        # Head phase update logic (reference table-driven behavior).
        quadrant = phase[2..1]
        rel_phase =
          mux(quadrant == lit(0, width: 2),
            cat(motor_phase[1..0], motor_phase[3..2]),
            mux(quadrant == lit(1, width: 2),
              cat(motor_phase[2..0], motor_phase[3]),
              mux(quadrant == lit(3, width: 2),
                cat(motor_phase[0], motor_phase[3..1]),
                motor_phase
              )
            )
          )

        phase_p1 = mux(phase == lit(139, width: 8), lit(139, width: 8), phase + lit(1, width: 8))
        phase_p2 = mux(phase >= lit(138, width: 8), lit(139, width: 8), phase + lit(2, width: 8))
        phase_p3 = mux(phase >= lit(137, width: 8), lit(139, width: 8), phase + lit(3, width: 8))
        phase_m1 = mux(phase == lit(0, width: 8), lit(0, width: 8), phase - lit(1, width: 8))
        phase_m2 = mux(phase < lit(2, width: 8), lit(0, width: 8), phase - lit(2, width: 8))
        phase_m3 = mux(phase < lit(3, width: 8), lit(0, width: 8), phase - lit(3, width: 8))

        odd_next =
          mux(rel_phase == lit(0x1, width: 4), phase_m3,
            mux(rel_phase == lit(0x2, width: 4), phase_m1,
              mux(rel_phase == lit(0x3, width: 4), phase_m2,
                mux(rel_phase == lit(0x4, width: 4), phase_p1,
                  mux(rel_phase == lit(0x5, width: 4), phase_m1,
                    mux(rel_phase == lit(0x7, width: 4), phase_m1,
                      mux(rel_phase == lit(0x8, width: 4), phase_p3,
                        mux(rel_phase == lit(0xA, width: 4), phase_p1,
                          mux(rel_phase == lit(0xB, width: 4), phase_m3, phase)
                        )
                      )
                    )
                  )
                )
              )
            )
          )

        even_next =
          mux(rel_phase == lit(0x1, width: 4), phase_m2,
            mux(rel_phase == lit(0x3, width: 4), phase_m1,
              mux(rel_phase == lit(0x4, width: 4), phase_p2,
                mux(rel_phase == lit(0x6, width: 4), phase_p1,
                  mux(rel_phase == lit(0x9, width: 4), phase_p1,
                    mux(rel_phase == lit(0xA, width: 4), phase_p2,
                      mux(rel_phase == lit(0xB, width: 4), phase_m2, phase)
                    )
                  )
                )
              )
            )
          )

        phase <= mux(phase[0], odd_next, even_next)
      end

      # Track RAM operations (separate clock domain)
      wire :track_mem_write_addr, width: 21
      wire :track_mem_addr, width: 21
      wire :ram_data, width: 8
      behavior do
        track_num = phase[7..2]

        # Drive active signals
        d1_active <= drive_on & ~drive2_select
        d2_active <= drive_on & drive2_select

        # Current track number output
        track <= track_num

        # Track address output (byte position within current track)
        track_addr <= track_byte_addr[14..1]

        # ROM address from low byte of address bus
        rom_addr <= a[7..0]

        # Compute base offset = track_num * 6656 (0x1A00 = 2^12 + 2^11 + 2^9)
        base_12 = cat(track_num, lit(0, width: 12))                       # << 12
        base_11 = cat(lit(0, width: 1), track_num, lit(0, width: 11))     # << 11
        base_9  = cat(lit(0, width: 3), track_num, lit(0, width: 9))      # << 9
        track_base = base_12 + base_11 + base_9

        # Write address for external track loader (writes to current track)
        track_mem_write_addr <= track_base + ram_write_addr

        # Read disk data when accessing C08C
        read_disk = device_select & (a[3..0] == lit(0xC, width: 4))

        # Read from track memory with computed address (track_base + (track_byte_addr >> 1))
        track_mem_addr <= track_base + track_byte_addr[14..1]

        # Data output mux
        # - ROM data when accessing $C6xx (io_select)
        # - Track data when reading disk and data-valid bit is 0
        # - Otherwise 0
        d_out <= mux(io_select,
          rom_dout,
          mux(read_disk & ~track_byte_addr[0],
            ram_data,
            lit(0, width: 8)
          )
        )
      end

      sync_write :track_memory,
        clock: :clk_14m,
        enable: :ram_we,
        addr: :track_mem_write_addr,
        data: :ram_di

      async_read :ram_data,
        from: :track_memory,
        addr: :track_mem_addr

      # Simulation helpers for disk image loading
      def load_track(track_num, data)
        return if track_num >= 35 || data.nil?

        data.each_with_index do |byte, i|
          break if i >= TRACK_SIZE
          mem_write(:track_memory, (track_num * TRACK_SIZE) + i, byte, 8)
        end
      end

      def read_track_byte(addr, track_num: 0)
        mem_read(:track_memory, (track_num * TRACK_SIZE) + (addr % TRACK_SIZE))
      end
    end
  end
  end
end
