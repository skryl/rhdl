# frozen_string_literal: true

# Headless runner factory for Game Boy emulation
# Creates runners for testing without terminal UI
#
# This provides the same runner creation logic as GameBoyTerminal
# but without any terminal/display dependencies.

require_relative 'hdl_runner'

module RHDL
  module Examples
    module GameBoy
      class HeadlessRunner
      attr_reader :runner, :mode, :sim_backend

      # Create a headless runner with the specified options
      # @param mode [Symbol] Simulation mode: :hdl, :verilog
      # @param sim [Symbol] Simulator backend: :ruby, :interpret, :jit, :compile
      def initialize(mode: :hdl, sim: :ruby)
        @mode = mode
        @sim_backend = sim

        # Create runner based on mode and sim backend
        @runner = case @mode
                  when :verilog
                    require_relative 'verilator_runner'
                    RHDL::Examples::GameBoy::VerilatorRunner.new
                  else  # :hdl (default)
                    if @sim_backend == :ruby
                      # Pure Ruby HDL simulation
                      RHDL::Examples::GameBoy::HdlRunner.new
                    else
                      # IR simulation with native backends (interpret, jit, compile)
                      require_relative 'ir_runner'
                      RHDL::Examples::GameBoy::IrRunner.new(backend: @sim_backend)
                    end
                  end
      end

      # Load ROM
      def load_rom(path_or_bytes, base_addr: 0)
        bytes = if path_or_bytes.is_a?(String) && !path_or_bytes.include?("\x00") && File.exist?(path_or_bytes)
                  File.binread(path_or_bytes)
                else
                  path_or_bytes
                end
        @runner.load_rom(bytes, base_addr: base_addr)
      end

      # Load RAM (for testing)
      def load_ram(bytes, base_addr:)
        @runner.load_ram(bytes, base_addr: base_addr)
      end

      # Reset the system
      def reset
        @runner.reset
      end

      # Run for specified number of steps/cycles
      def run_steps(steps)
        @runner.run_steps(steps)
      end

      # Check if system is halted
      def halted?
        @runner.halted?
      end

      # Get CPU state
      def cpu_state
        @runner.cpu_state
      end

      # Get cycle count
      def cycle_count
        @runner.cycle_count
      end

      def frame_count
        return nil unless @runner.respond_to?(:frame_count)

        @runner.frame_count
      end

      # Check if using native implementation
      def native?
        @runner.native?
      end

      # Get simulator type
      def simulator_type
        @runner.simulator_type
      end

      # Get backend
      def backend
        case @mode
        when :hdl
          @sim_backend
        when :verilog
          nil
        else
          @sim_backend
        end
      end

      # Get ROM size (for verification)
      def rom_size
        if @runner.respond_to?(:rom) && @runner.rom
          @runner.rom.size
        elsif @runner.instance_variable_defined?(:@rom)
          rom = @runner.instance_variable_get(:@rom)
          rom ? rom.size : 0
        else
          0
        end
      end

      # Create a simple test ROM
      # This is a minimal ROM that just loops
      def self.create_test_rom
        # Minimal Game Boy ROM header + simple loop
        rom = Array.new(0x150, 0)

        # Entry point at 0x100 - jump to 0x150
        rom[0x100] = 0x00  # NOP
        rom[0x101] = 0xC3  # JP 0x0150
        rom[0x102] = 0x50
        rom[0x103] = 0x01

        # Nintendo logo (required for boot)
        logo = [
          0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
          0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
          0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
          0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
          0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
          0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
        ]
        logo.each_with_index { |b, i| rom[0x104 + i] = b }

        # Title (16 bytes at 0x134)
        title = "TEST"
        title.bytes.each_with_index { |b, i| rom[0x134 + i] = b }

        # Cartridge type (0x147) - ROM only
        rom[0x147] = 0x00

        # ROM size (0x148) - 32KB
        rom[0x148] = 0x00

        # RAM size (0x149) - None
        rom[0x149] = 0x00

        # Simple loop at 0x150
        rom[0x150] = 0x00  # NOP
        rom[0x151] = 0x18  # JR -2 (infinite loop)
        rom[0x152] = 0xFE

        # Header checksum (0x14D)
        checksum = 0
        (0x134..0x14C).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
        rom[0x14D] = checksum

        rom
      end

      # Create a headless runner with test ROM loaded
      def self.with_test_rom(mode: :hdl, sim: :ruby)
        runner = new(mode: mode, sim: sim)
        test_rom = create_test_rom
        runner.load_rom(test_rom)
        runner
      end
      end
    end
  end
end
