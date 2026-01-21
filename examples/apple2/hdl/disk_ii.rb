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

require 'rhdl'

module RHDL
  module Apple2
    # Disk II ROM (256 bytes boot ROM at $C600-$C6FF)
    # Pure DSL component - ROM data loaded via simulation helper or initial: parameter
    class DiskIIROM < Component
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

      # Simulation helper: load ROM data at runtime (non-synthesizable)
      def load_rom(data)
        data.each_with_index do |byte, i|
          break if i >= 256
          mem_write(:rom, i, byte, 8)
        end
      end
    end

    # Main Disk II Controller
    class DiskII < SequentialComponent
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

      # Track buffer (6656 bytes per track)
      TRACK_SIZE = 6656
      memory :track_memory, depth: TRACK_SIZE, width: 8

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
      wire :track_byte_addr, width: 15
      wire :byte_delay, width: 6

      sequential clock: :clk_2m, reset: :reset, reset_values: {
        motor_phase: 0,
        drive_on: 0,
        drive2_select: 0,
        q6: 0,
        q7: 0,
        phase: 70,                       # Head position (0-139, 2 per track)
        track_byte_addr: 0,
        byte_delay: 0
      } do
        # I/O register control
        io_access = pre_phase_zero & device_select

        # Phase control (C080-C087)
        phase_access = io_access & ~a[3]
        phase_bit = a[2..1]
        phase_value = a[0]

        motor_phase <= mux(phase_access,
          # Set or clear the appropriate phase bit
          (motor_phase & ~(lit(1, width: 4) << phase_bit)) |
          (mux(phase_value, lit(1, width: 4), lit(0, width: 4)) << phase_bit),
          motor_phase
        )

        # Control registers (C088-C08F)
        ctrl_access = io_access & a[3]
        ctrl_reg = a[2..1]

        drive_on <= mux(ctrl_access & (ctrl_reg == lit(0, width: 2)),
          a[0], drive_on
        )

        drive2_select <= mux(ctrl_access & (ctrl_reg == lit(1, width: 2)),
          a[0], drive2_select
        )

        q6 <= mux(ctrl_access & (ctrl_reg == lit(2, width: 2)),
          a[0], q6
        )

        q7 <= mux(ctrl_access & (ctrl_reg == lit(3, width: 2)),
          a[0], q7
        )

        # Head stepper motor logic
        # Phase changes move the head to different tracks
        # There are 70 phases for 35 tracks (2 phases per track)

        # Calculate relative phase based on current position
        current_quadrant = phase[2..1]

        # Phase change calculation (simplified)
        # In the full implementation, this involves looking at which
        # motor phases are active and calculating the direction

        # Track byte address counter
        # Simulates disk spinning - one new byte every 32 CPU cycles
        byte_delay <= byte_delay - lit(1, width: 6)

        read_disk = device_select & (a[3..0] == lit(0xC, width: 4))

        # Advance to next byte when read or when delay expires
        advance = (read_disk & pre_phase_zero) | (byte_delay == lit(0, width: 6))

        track_byte_addr_next = mux(track_byte_addr == lit(0x33FE, width: 15),
          lit(0, width: 15),
          track_byte_addr + lit(1, width: 15)
        )

        track_byte_addr <= mux(advance, track_byte_addr_next, track_byte_addr)
        byte_delay <= mux(advance, lit(0, width: 6), byte_delay)
      end

      # Track RAM operations (separate clock domain)
      sync_write :track_memory,
        clock: :clk_14m,
        enable: :ram_we,
        addr: :ram_write_addr,
        data: :ram_di

      # Combinational outputs
      behavior do
        # Drive active signals
        d1_active <= drive_on & ~drive2_select
        d2_active <= drive_on & drive2_select

        # Current track number
        track <= phase[7..2]

        # Track address output
        track_addr <= track_byte_addr[14..1]

        # ROM address from low byte of address bus
        rom_addr <= a[7..0]

        # Read disk data when accessing C08C
        read_disk = device_select & (a[3..0] == lit(0xC, width: 4))

        # Data output mux
        # - ROM data when accessing $C6xx (io_select)
        # - Track data when reading disk (valid when addr bit 0 is 0)
        # - Otherwise 0

        # Read from track memory with computed address (track_byte_addr >> 1)
        ram_data = mem_read_expr(:track_memory, track_byte_addr[14..1], width: 8)

        d_out <= mux(io_select,
          rom_dout,
          mux(read_disk & ~track_byte_addr[0],
            ram_data,
            lit(0, width: 8)
          )
        )
      end

      # Helper methods for disk image loading
      def load_track(track_num, data)
        return if track_num >= 35 || data.nil?

        data.each_with_index do |byte, i|
          break if i >= TRACK_SIZE
          mem_write(:track_memory, i, byte, 8)
        end
      end

      def read_track_byte(addr)
        mem_read(:track_memory, addr & (TRACK_SIZE - 1))
      end
    end
  end
end
