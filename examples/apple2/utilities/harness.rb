# frozen_string_literal: true

# Apple II HDL Harness
# Wraps the Apple2 HDL component for use in emulation

require_relative '../hdl/apple2'

module RHDL
  module Apple2
    # HDL-based runner using cycle-accurate Apple2 simulation
    class Runner
      attr_reader :apple2, :ram

      # Text page constants
      TEXT_PAGE1_START = 0x0400
      TEXT_PAGE1_END = 0x07FF

      def initialize
        @apple2 = Apple2.new('apple2')
        @ram = Array.new(48 * 1024, 0)  # 48KB RAM
        @cycles = 0
        @halted = false
        @text_page_dirty = false
        @key_data = 0
        @key_ready = false

        # Initialize system inputs
        @apple2.set_input(:clk_14m, 0)
        @apple2.set_input(:flash_clk, 0)
        @apple2.set_input(:reset, 0)
        @apple2.set_input(:ram_do, 0)
        @apple2.set_input(:pd, 0)
        @apple2.set_input(:k, 0)
        @apple2.set_input(:gameport, 0)
        @apple2.set_input(:pause, 0)

        # Track Q3 for cycle counting
        @prev_q3 = 0
      end

      # Load ROM data into the Apple2 component
      def load_rom(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)
        @apple2.load_rom(bytes)
      end

      # Load data into RAM
      def load_ram(bytes, base_addr:)
        bytes = bytes.bytes if bytes.is_a?(String)
        bytes.each_with_index do |byte, i|
          addr = base_addr + i
          @ram[addr] = byte if addr < @ram.size
        end
      end

      # Disk loading (stub - not yet implemented for HDL)
      def load_disk(path_or_bytes, drive: 0)
        # TODO: Implement disk controller integration
        warn "Disk loading not yet implemented for HDL Apple2"
      end

      def disk_loaded?(drive: 0)
        false
      end

      # Reset the system
      def reset
        @apple2.set_input(:reset, 1)
        run_14m_cycles(14)  # Hold reset for a few cycles
        @apple2.set_input(:reset, 0)
        run_14m_cycles(14 * 10)  # Let system settle
        @cycles = 0
        @halted = false
      end

      # Run N CPU cycles (approximately)
      # Each CPU cycle is ~7 14MHz cycles
      def run_steps(steps)
        steps.times do
          run_cpu_cycle
        end
      end

      # Run a single CPU cycle
      def run_cpu_cycle
        # Run 14MHz cycles until we see a Q3 rising edge with enable
        14.times do
          run_14m_cycle
        end
        @cycles += 1
      end

      # Run a single 14MHz clock cycle
      def run_14m_cycle
        # Update keyboard input
        @apple2.set_input(:k, @key_ready ? (@key_data | 0x80) : 0)

        # Falling edge
        @apple2.set_input(:clk_14m, 0)
        @apple2.propagate

        # Provide RAM data
        ram_addr = @apple2.get_output(:ram_addr)
        if ram_addr < @ram.size
          @apple2.set_input(:ram_do, @ram[ram_addr])
        end
        @apple2.propagate

        # Rising edge
        @apple2.set_input(:clk_14m, 1)
        @apple2.propagate

        # Handle RAM writes
        ram_we = @apple2.get_output(:ram_we)
        if ram_we == 1
          write_addr = @apple2.get_output(:ram_addr)
          if write_addr < @ram.size
            @ram[write_addr] = @apple2.get_output(:d)
            # Mark text page dirty
            if write_addr >= TEXT_PAGE1_START && write_addr <= TEXT_PAGE1_END
              @text_page_dirty = true
            end
          end
        end

        # Check for keyboard strobe clear
        if @apple2.get_output(:read_key) == 1
          @key_ready = false
        end
      end

      # Run N 14MHz cycles
      def run_14m_cycles(n)
        n.times { run_14m_cycle }
      end

      # Inject a key into the keyboard buffer
      def inject_key(ascii)
        @key_data = ascii & 0x7F
        @key_ready = true
      end

      def key_ready?
        @key_ready
      end

      def clear_key
        @key_ready = false
      end

      # Read the text page as a 2D array of character codes
      def read_screen_array
        result = []
        24.times do |row|
          line = []
          base = text_line_address(row)
          40.times do |col|
            addr = base + col
            line << (@ram[addr] || 0)
          end
          result << line
        end
        result
      end

      # Read the text page as 24 lines of strings
      def read_screen
        read_screen_array.map do |line|
          line.map { |c| ((c & 0x7F) >= 0x20 ? (c & 0x7F).chr : ' ') }.join
        end
      end

      def screen_dirty?
        @text_page_dirty
      end

      def clear_screen_dirty
        @text_page_dirty = false
      end

      # Get CPU state for debugging
      def cpu_state
        {
          pc: @apple2.get_output(:pc_debug),
          a: @apple2.get_output(:a_debug),
          x: @apple2.get_output(:x_debug),
          y: @apple2.get_output(:y_debug),
          sp: 0xFF,  # TODO: Add S register debug output
          p: 0,      # TODO: Add P register debug output
          cycles: @cycles,
          halted: @halted,
          simulator_type: :hdl_apple2
        }
      end

      def halted?
        @halted
      end

      def cycle_count
        @cycles
      end

      def simulator_type
        :hdl_apple2
      end

      def native?
        false
      end

      # Bus-like interface for compatibility
      def bus
        self
      end

      # Stub methods for compatibility with Apple2Terminal
      def tick(cycles)
        # No-op for HDL
      end

      def disk_controller
        @disk_controller ||= DiskControllerStub.new
      end

      def speaker
        @speaker ||= SpeakerStub.new
      end

      def display_mode
        :text
      end

      def start_audio
        # No-op for now
      end

      def stop_audio
        # No-op for now
      end

      def read(addr)
        if addr < @ram.size
          @ram[addr]
        else
          0
        end
      end

      def write(addr, value)
        if addr < @ram.size
          @ram[addr] = value & 0xFF
        end
      end

      private

      # Apple II text screen line address calculation
      # The text screen uses an interleaved memory layout
      def text_line_address(row)
        # Apple II text page memory layout (base $0400)
        # Lines are interleaved in groups of 8
        group = row / 8
        line_in_group = row % 8
        TEXT_PAGE1_START + (line_in_group * 0x80) + (group * 0x28)
      end
    end

    # Stub for disk controller (not yet implemented)
    class DiskControllerStub
      def track
        0
      end

      def motor_on
        false
      end
    end

    # Stub for speaker (not yet implemented)
    class SpeakerStub
      def status
        "OFF"
      end

      def active?
        false
      end

      def toggle_count
        0
      end

      def samples_written
        0
      end
    end
  end
end
