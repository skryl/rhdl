# frozen_string_literal: true

# Headless runner factory for Apple II emulation
# Creates runners for testing without terminal UI
#
# This provides the same runner creation logic as Apple2HDLTerminal
# but without any terminal/display dependencies.

require_relative 'ruby_runner'

module RHDL
  module Examples
    module Apple2
      class HeadlessRunner
      attr_reader :runner, :mode, :sim_backend

      # Create a headless runner with the specified options
      # @param mode [Symbol] Simulation mode: :ruby, :ir, :netlist, :verilog
      # @param sim [Symbol] Simulator backend for :ir/:netlist: :interpret, :jit, :compile
      # @param sub_cycles [Integer] Sub-cycles per CPU cycle (for IR backends)
      def initialize(mode: :ruby, sim: nil, sub_cycles: 14)
        @mode = mode
        @sim_backend = sim || default_backend(mode)
        @sub_cycles = sub_cycles

        # Create runner based on mode and sim backend
        @runner = case mode
                  when :ruby
                    RHDL::Examples::Apple2::RubyRunner.new
                  when :ir
                    require_relative 'ir_runner'
                    RHDL::Examples::Apple2::IrRunner.new(backend: normalize_native_backend(@sim_backend), sub_cycles: sub_cycles)
                  when :netlist
                    require_relative 'netlist_runner'
                    RHDL::Examples::Apple2::NetlistRunner.new(backend: normalize_native_backend(@sim_backend))
                  when :verilog
                    require_relative 'verilator_runner'
                    RHDL::Examples::Apple2::VerilogRunner.new(sub_cycles: sub_cycles)
                  else
                    raise ArgumentError, "Unknown mode: #{mode}. Valid modes: ruby, ir, netlist, verilog"
                  end
      end

      # Load ROM into memory
      def load_rom(path_or_bytes, base_addr: 0xD000)
        bytes = path_or_bytes.is_a?(String) && File.exist?(path_or_bytes) ? File.binread(path_or_bytes) : path_or_bytes
        @runner.load_rom(bytes, base_addr: base_addr)
      end

      # Load program into RAM
      def load_program(path_or_bytes, base_addr: 0x0800)
        bytes = path_or_bytes.is_a?(String) && File.exist?(path_or_bytes) ? File.binread(path_or_bytes) : path_or_bytes
        @runner.load_ram(bytes, base_addr: base_addr)
      end

      # Load program bytes directly
      def load_program_bytes(bytes, base_addr: 0x0800)
        @runner.load_ram(bytes, base_addr: base_addr)
      end

      # Set reset vector to the given address
      def setup_reset_vector(addr)
        @runner.write(0xFFFC, addr & 0xFF)
        @runner.write(0xFFFD, (addr >> 8) & 0xFF)
      end

      # Load disk image
      def load_disk(path, drive: 0)
        @runner.load_disk(path, drive: drive)
      end

      # Load memory dump at address
      def load_memdump(path, pc: 0x0800, use_appleiigo: false)
        bytes = File.binread(path)
        @runner.load_ram(bytes, base_addr: 0x0000)

        if use_appleiigo
          rom_file = File.expand_path('../../software/roms/appleiigo.rom', __dir__)
          load_rom(rom_file) if File.exist?(rom_file)
        end

        setup_reset_vector(pc)
      end

      # Reset the CPU
      def reset
        @runner.reset
      end

      # Run for specified number of steps/cycles
      def run_steps(steps)
        @runner.run_steps(steps)
      end

      # Check if CPU is halted
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

      # Check if using native implementation
      def native?
        @runner.native?
      end

      # Get simulator type
      def simulator_type
        @runner.simulator_type
      end

      # Delegate keyboard input to runner
      def inject_key(ascii)
        @runner.inject_key(ascii)
      end

      # Delegate screen methods to runner
      def read_screen_array
        @runner.read_screen_array
      end

      def read_screen
        @runner.read_screen
      end

      def screen_dirty?
        @runner.screen_dirty?
      end

      def clear_screen_dirty
        @runner.clear_screen_dirty
      end

      # Delegate hi-res rendering to runner
      def render_hires_color(chars_wide: 140, composite: false)
        @runner.render_hires_color(chars_wide: chars_wide, composite: composite)
      end

      def render_hires_braille(chars_wide: 80, invert: false)
        @runner.render_hires_braille(chars_wide: chars_wide, invert: invert)
      end

      # Delegate disk controller access
      def disk_controller
        @runner.disk_controller
      end

      # Delegate speaker access
      def speaker
        @runner.speaker
      end

      def start_audio
        @runner.start_audio
      end

      def stop_audio
        @runner.stop_audio
      end

      # Delegate memory write
      def write(addr, value)
        @runner.write(addr, value)
      end

      # Delegate memory read
      def read(addr)
        @runner.read(addr)
      end

      # Delegate bus access
      def bus
        @runner.bus
      end

      # Get backend
      def backend
        case @mode
        when :ruby, :ir
          @sim_backend
        when :netlist
          @sim_backend
        when :verilog
          nil
        else
          @sim_backend
        end
      end

      # Get memory sample for verification
      def memory_sample
        bus = @runner.bus
        {
          zero_page: (0...256).map { |i| bus.read(i) },
          stack: (0...256).map { |i| bus.read(0x0100 + i) },
          text_page: (0...1024).map { |i| bus.read(0x0400 + i) },
          program_area: (0...256).map { |i| bus.read(0x0800 + i) },
          reset_vector: [bus.read(0xFFFC), bus.read(0xFFFD)]
        }
      end

      # Create a demo program (same as CLI --demo)
      def self.create_demo_program
        # Simple "Hello Apple2" display program
        [
          0xA9, 0xC8,       # LDA #'H' (with high bit set for Apple II)
          0x8D, 0x00, 0x04, # STA $0400
          0xA9, 0xC5,       # LDA #'E'
          0x8D, 0x01, 0x04, # STA $0401
          0xA9, 0xCC,       # LDA #'L'
          0x8D, 0x02, 0x04, # STA $0402
          0xA9, 0xCC,       # LDA #'L'
          0x8D, 0x03, 0x04, # STA $0403
          0xA9, 0xCF,       # LDA #'O'
          0x8D, 0x04, 0x04, # STA $0404
          0x00              # BRK
        ]
      end

      # Create a headless runner with demo program loaded
      def self.with_demo(mode: :ruby, sim: nil, sub_cycles: 14)
        runner = new(mode: mode, sim: sim, sub_cycles: sub_cycles)
        demo = create_demo_program
        runner.load_program_bytes(demo, base_addr: 0x0800)
        runner.setup_reset_vector(0x0800)
        runner
      end

      # Paths for Karateka resources
      KARATEKA_ROM_PATH = File.expand_path('../../software/roms/appleiigo.rom', __dir__)
      KARATEKA_MEM_PATH = File.expand_path('../../software/disks/karateka_mem.bin', __dir__)

      # Check if Karateka resources are available
      def self.karateka_available?
        File.exist?(KARATEKA_ROM_PATH) && File.exist?(KARATEKA_MEM_PATH)
      end

      # Check if verilator is available
      def self.verilator_available?
        ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
          File.executable?(File.join(path, 'verilator'))
        end
      end

      # Create a headless runner with Karateka loaded (from memory dump)
      # This loads the game state from a memory dump, bypassing disk I/O
      def self.with_karateka(mode: :ruby, sim: nil, sub_cycles: 14)
        raise "Karateka ROM not found at #{KARATEKA_ROM_PATH}" unless File.exist?(KARATEKA_ROM_PATH)
        raise "Karateka memory dump not found at #{KARATEKA_MEM_PATH}" unless File.exist?(KARATEKA_MEM_PATH)

        runner = new(mode: mode, sim: sim, sub_cycles: sub_cycles)

        # Load ROM with modified reset vector pointing to game entry point ($B82A)
        rom_data = File.binread(KARATEKA_ROM_PATH).bytes
        rom_data[0x2FFC] = 0x2A  # low byte of $B82A
        rom_data[0x2FFD] = 0xB8  # high byte of $B82A
        runner.load_rom(rom_data, base_addr: 0xD000)

        # Load Karateka memory dump
        mem_data = File.binread(KARATEKA_MEM_PATH).bytes
        runner.load_program_bytes(mem_data.first(48 * 1024), base_addr: 0x0000)

        runner
      end

      private

      def normalize_native_backend(backend)
        case backend
        when :interpret, :jit, :compile
          backend
        else
          raise ArgumentError, "Invalid backend #{backend.inspect} for #{mode} mode. Use :interpret, :jit, or :compile."
        end
      end

      def default_backend(mode)
        case mode
        when :ruby then :ruby
        when :ir, :netlist then :compile
        when :verilog then nil
        else
          raise ArgumentError, "Unknown mode: #{mode}. Valid modes: ruby, ir, netlist, verilog"
        end
      end
    end
  end
  end
end
