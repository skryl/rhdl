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
      output :half_track, width: 7       # Half-track position (0-69)
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
      wire :prev_motor_phase, width: 4  # Track previous motor phase for edge detection
      wire :drive_on
      wire :drive2_select
      wire :q6
      wire :q7
      wire :phase, width: 8
      wire :track_byte_addr, width: 15
      wire :byte_delay, width: 9        # 9 bits for 0-430 range
      wire :data_valid                   # Indicates new byte is ready (high bit handshaking)
      wire :read_latch_prev              # Previous read_latch state for edge detection

      # Run on clk_14m for consistent timing
      # At 14.31818 MHz, with 6656 bytes per track at 300 RPM:
      # 14318180 / (6656 * 5) = ~430 cycles per byte
      BYTE_DELAY_MAX = 429

      sequential clock: :clk_14m, reset: :reset, reset_values: {
        motor_phase: 0,
        prev_motor_phase: 0,
        drive_on: 0,
        drive2_select: 0,
        q6: 0,
        q7: 0,
        phase: 0,                        # Head position (0-69 half-tracks, for 35 tracks)
        track_byte_addr: 0,
        byte_delay: 0,
        data_valid: 0,                   # Start with no data valid
        read_latch_prev: 0               # Previous read_latch state
      } do
        # I/O register control
        io_access = pre_phase_zero & device_select

        # Phase control (C080-C087)
        # Calculate new motor_phase value first (needed for phase change detection)
        phase_access = io_access & ~a[3]
        phase_bit = a[2..1]
        phase_value = a[0]

        new_motor_phase = mux(phase_access,
          # Set or clear the appropriate phase bit
          (motor_phase & ~(lit(1, width: 4) << phase_bit)) |
          (mux(phase_value, lit(1, width: 4), lit(0, width: 4)) << phase_bit),
          motor_phase
        )

        motor_phase <= new_motor_phase

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
        # There are 70 half-tracks for 35 tracks (2 half-tracks per track)
        # The motor_phase bits indicate which of 4 magnets are energized
        # The head moves toward the energized magnet
        #
        # IMPORTANT: The stepper only moves when motor_phase CHANGES.
        # The magnet pulls the head to align with it. Once aligned, no more
        # movement occurs until a different magnet is energized.

        # Detect motor phase change (only step when phases change)
        # Use new_motor_phase (what we're setting) vs prev_motor_phase (previous cycle)
        phase_changed = (new_motor_phase != prev_motor_phase)

        # Update prev_motor_phase to track changes
        prev_motor_phase <= new_motor_phase

        # Current quadrant (0-3) based on head position
        # half_track 0-1 = quadrant 0, 2-3 = quadrant 1, etc.
        current_quadrant = (phase >> lit(1, width: 8)) & lit(3, width: 8)

        # Find the lowest active motor phase (priority encoder)
        # Use new_motor_phase for current state detection
        # motor_phase bit 0 = phase 0 magnet, bit 1 = phase 1, etc.
        active_phase = mux(new_motor_phase[0],
          lit(0, width: 2),
          mux(new_motor_phase[1],
            lit(1, width: 2),
            mux(new_motor_phase[2],
              lit(2, width: 2),
              lit(3, width: 2)
            )
          )
        )

        # Any motor phase active?
        any_phase_active = new_motor_phase[0] | new_motor_phase[1] | new_motor_phase[2] | new_motor_phase[3]

        # Calculate phase difference (where does the active magnet want us to go?)
        # If active_phase = (current_quadrant + 1) % 4, step inward (toward higher tracks)
        # If active_phase = (current_quadrant - 1) % 4 = (current_quadrant + 3) % 4, step outward
        next_quadrant = (current_quadrant + lit(1, width: 8)) & lit(3, width: 8)
        prev_quadrant = (current_quadrant + lit(3, width: 8)) & lit(3, width: 8)

        # Only step when phases have changed
        step_in = phase_changed & any_phase_active & (active_phase == next_quadrant[1..0])
        step_out = phase_changed & any_phase_active & (active_phase == prev_quadrant[1..0])

        # Update phase with clamping (0 to 69 for 35 tracks)
        phase_plus_one = phase + lit(1, width: 8)
        phase_minus_one = phase - lit(1, width: 8)

        phase <= mux(step_in & (phase < lit(69, width: 8)),
          phase_plus_one,
          mux(step_out & (phase > lit(0, width: 8)),
            phase_minus_one,
            phase
          )
        )

        # Track byte address counter
        # Simulates disk spinning at constant speed
        #
        # The real Disk II provides a new byte every ~32 CPU cycles (4μs).
        # The disk head position advances based on rotation timing, NOT on reads.
        # Reading the data latch returns the current byte at the head position.
        #
        # byte_delay counts down and advances position when it expires.
        # At 14.31818 MHz with 6656 bytes per track at 300 RPM:
        # 14318180 / (6656 * 5) = ~430 cycles per byte

        # Advance to next byte ONLY when timer expires (not on reads)
        # This correctly models constant disk rotation
        advance = (byte_delay == lit(0, width: 9))

        # track_byte_addr is a simple counter that wraps at TRACK_SIZE
        # No division needed - each increment is one byte
        track_byte_addr_next = mux(track_byte_addr >= lit(TRACK_SIZE - 1, width: 15),
          lit(0, width: 15),
          track_byte_addr + lit(1, width: 15)
        )

        track_byte_addr <= mux(advance, track_byte_addr_next, track_byte_addr)

        # byte_delay: reset to BYTE_DELAY_MAX when advancing, otherwise decrement
        byte_delay <= mux(advance,
          lit(BYTE_DELAY_MAX, width: 9),  # Reset to 429 when advancing
          byte_delay - lit(1, width: 9)   # Decrement otherwise
        )

        # Data valid handshaking for high bit of data latch
        # The real Disk II clears the high bit after a read and sets it when new data arrives.
        # This makes the boot ROM's BPL loop wait for the next byte.
        #
        # IMPORTANT: We use edge detection for read_latch because:
        # - read_latch is true for ~14 clk_14m cycles during each CPU read
        # - Without edge detection, data_valid would be cleared immediately after advance sets it
        # - With edge detection, we only clear data_valid on the FIRST cycle of a read
        # - This gives the CPU a full window to see data_valid=1 before the next read clears it
        #
        # Detect read of data latch (C0EC or C08C with X offset)
        read_latch = device_select & (a[3..0] == lit(0xC, width: 4))

        # Rising edge detection: clear data_valid only on first cycle of read
        read_edge = read_latch & ~read_latch_prev
        read_latch_prev <= read_latch

        # Set data_valid when new byte arrives, clear on rising edge of read
        # advance takes priority: if new byte arrives during a read, data_valid stays 1
        data_valid <= mux(advance,
          lit(1, width: 1),               # New byte ready
          mux(read_edge,
            lit(0, width: 1),             # CPU read (rising edge), clear valid
            data_valid
          )
        )
      end

      # Track RAM operations (separate clock domain)
      sync_write :track_memory,
        clock: :clk_14m,
        enable: :ram_we,
        addr: :ram_write_addr,
        data: :ram_di

      # Combinational outputs (all combinational logic in ONE behavior block)
      behavior do
        # Drive active signals
        d1_active <= drive_on & ~drive2_select
        d2_active <= drive_on & drive2_select

        # Current track number (phase / 2)
        # phase is 0-69 (half-tracks), track is 0-34
        track <= phase[6..1]

        # Half-track position (for debugging/track loading)
        half_track <= phase[6..0]

        # Track address output (direct byte address, 0-6655)
        track_addr <= track_byte_addr[13..0]

        # ROM address from low byte of address bus (combinational)
        rom_addr <= a[7..0]

        # Read disk data when accessing C08C
        read_disk = device_select & (a[3..0] == lit(0xC, width: 4))

        # Data output mux
        # - ROM data when accessing $C6xx (io_select)
        # - Track data when reading disk (with data_valid handshaking)
        # - Otherwise 0
        #
        # The disk controller advances track_byte_addr on a timer (every ~30 CPU cycles)
        # independent of reads. Reading simply returns the current byte at the head position.
        #
        # The data_valid flag implements the Disk II's high bit handshaking:
        # - When a new byte arrives, data_valid is set and the full byte is returned
        # - When the CPU reads, data_valid is cleared and high bit is cleared
        # - The boot ROM's BPL loop waits for the high bit to be set (new data)

        # Read from track memory with direct address (0-6655)
        ram_data = mem_read_expr(:track_memory, track_byte_addr[12..0], width: 8)

        # Handshaking: The Disk II controller uses bit 7 to indicate fresh data.
        #
        # Instead of complex edge detection (which has timing issues in IR compiler),
        # we use byte_delay to determine freshness. When byte_delay is high (>= 330),
        # we're within ~100 clk_14m cycles (~7 CPU cycles) of the advance, so it's fresh.
        # This gives the CPU a window to complete its LDA instruction and see the fresh byte.
        #
        # The boot ROM loop is ~10 CPU cycles, so a 7-cycle window should catch exactly
        # one read per byte while preventing multiple reads from seeing bit 7 set.
        #
        # Note: byte_delay counts DOWN from 429, so high values mean recent advance
        byte_fresh = (byte_delay > lit(329, width: 9))  # ~100 cycle window

        disk_data = mux(byte_fresh,
          ram_data,                              # Fresh byte: full nibble
          ram_data & lit(0x7F, width: 8)         # Stale byte: clear bit 7
        )

        d_out <= mux(io_select,
          rom_dout,
          mux(read_disk,
            disk_data,
            lit(0, width: 8)
          )
        )
      end

      # Simulation helpers for disk image loading
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
