# frozen_string_literal: true

# Headless runner factory for MOS6502 emulation.
# Creates runners for testing without terminal UI.

require_relative '../apple2/harness'
require_relative 'isa_runner'
require_relative 'ruby_runner'

module RHDL
  module Examples
    module MOS6502
      class HeadlessRunner
        attr_reader :runner, :mode, :sim_backend

        # @param mode [Symbol] :isa, :ruby, :ir, :netlist, :verilog
        # @param sim [Symbol, nil]
        #   :isa    -> :native or :ruby
        #   :ruby   -> :ruby
        #   :ir     -> :interpret, :jit, :compile
        #   :verilog -> ignored (nil)
        def initialize(mode: :isa, sim: nil)
          @mode = mode
          @sim_backend = sim || default_backend(mode)

          @runner = case mode
                    when :isa
                      build_isa_runner(normalize_isa_backend(@sim_backend))
                    when :ruby
                      normalize_ruby_backend(@sim_backend)
                      RHDL::Examples::MOS6502::RubyRunner.new
                    when :ir
                      require_relative 'ir_runner'
                      RHDL::Examples::MOS6502::IrRunner.new(normalize_ir_backend(@sim_backend))
                    when :netlist
                      raise "Netlist mode not yet implemented for MOS6502"
                    when :verilog
                      require_relative 'verilator_runner'
                      RHDL::Examples::MOS6502::VerilogRunner.new
                    else
                      raise "Unknown mode: #{mode}. Valid modes: isa, ruby, ir, netlist, verilog"
                    end
        end

        # Load ROM into memory
        def load_rom(path_or_bytes, base_addr: 0xF800)
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
          if @runner.respond_to?(:set_reset_vector)
            @runner.set_reset_vector(addr)
          elsif @runner.respond_to?(:write_memory)
            @runner.write_memory(0xFFFC, addr & 0xFF)
            @runner.write_memory(0xFFFD, (addr >> 8) & 0xFF)
          else
            @runner.bus.write(0xFFFC, addr & 0xFF)
            @runner.bus.write(0xFFFD, (addr >> 8) & 0xFF)
          end
        end

        # Load disk image
        def load_disk(path, drive: 0)
          @runner.load_disk(path, drive: drive)
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

        # Delegate keyboard input
        def inject_key(ascii)
          @runner.inject_key(ascii)
        end

        # Delegate screen methods
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

        # Delegate bus access
        def bus
          @runner.bus
        end

        # Delegate audio control
        def start_audio
          if @runner.respond_to?(:start_audio)
            @runner.start_audio
          elsif @runner.respond_to?(:bus) && @runner.bus.respond_to?(:start_audio)
            @runner.bus.start_audio
          end
        end

        def stop_audio
          if @runner.respond_to?(:stop_audio)
            @runner.stop_audio
          elsif @runner.respond_to?(:bus) && @runner.bus.respond_to?(:stop_audio)
            @runner.bus.stop_audio
          end
        end

        # Get configured backend
        def backend
          case @mode
          when :isa, :ruby, :ir, :netlist
            @sim_backend
          when :verilog
            nil
          end
        end

        # Get memory sample for verification
        def memory_sample
          read_fn = if @runner.respond_to?(:read_memory)
                      ->(addr) { @runner.read_memory(addr) }
                    else
                      ->(addr) { @runner.bus.read(addr) }
                    end

          {
            zero_page: (0...256).map { |i| read_fn.call(i) },
            stack: (0...256).map { |i| read_fn.call(0x0100 + i) },
            text_page: (0...1024).map { |i| read_fn.call(0x0400 + i) },
            program_area: (0...256).map { |i| read_fn.call(0x0800 + i) },
            reset_vector: [read_fn.call(0xFFFC), read_fn.call(0xFFFD)]
          }
        end

        # Create a demo program (same as CLI --demo)
        def self.create_demo_program
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
        def self.with_demo(mode: :isa, sim: nil)
          runner = new(mode: mode, sim: sim)
          demo = create_demo_program
          runner.load_program_bytes(demo, base_addr: 0x0800)
          runner.setup_reset_vector(0x0800)
          runner
        end

        # Read a byte from memory
        def read(addr)
          if @runner.respond_to?(:read_memory)
            @runner.read_memory(addr)
          else
            @runner.bus.read(addr)
          end
        end

        KARATEKA_ROM_PATH = File.expand_path('../../software/roms/appleiigo.rom', __dir__)
        KARATEKA_MEM_PATH = File.expand_path('../../software/disks/karateka_mem.bin', __dir__)

        def self.karateka_available?
          File.exist?(KARATEKA_ROM_PATH) && File.exist?(KARATEKA_MEM_PATH)
        end

        def self.verilator_available?
          ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
            File.executable?(File.join(path, 'verilator'))
          end
        end

        # Create a headless runner with Karateka loaded (from memory dump)
        def self.with_karateka(mode: :isa, sim: nil)
          raise "Karateka ROM not found at #{KARATEKA_ROM_PATH}" unless File.exist?(KARATEKA_ROM_PATH)
          raise "Karateka memory dump not found at #{KARATEKA_MEM_PATH}" unless File.exist?(KARATEKA_MEM_PATH)

          runner = new(mode: mode, sim: sim)

          rom_data = File.binread(KARATEKA_ROM_PATH).bytes
          rom_data[0x2FFC] = 0x2A
          rom_data[0x2FFD] = 0xB8
          runner.load_rom(rom_data, base_addr: 0xD000)

          mem_data = File.binread(KARATEKA_MEM_PATH).bytes
          runner.load_program_bytes(mem_data.first(48 * 1024), base_addr: 0x0000)

          runner
        end

        private

        def build_isa_runner(backend)
          case backend
          when :native
            unless RHDL::Examples::MOS6502::NATIVE_AVAILABLE
              raise "ISA backend :native requested but native extension is unavailable. Use --sim ruby or build native extensions."
            end

            isa_runner = RHDL::Examples::MOS6502::Apple2Harness::ISARunner.new
            unless isa_runner.native?
              raise "ISA backend :native requested but runner is not native. Fallback is disabled."
            end
            isa_runner
          when :ruby
            bus = RHDL::Examples::MOS6502::Apple2Bus.new("apple2_bus")
            cpu = RHDL::Examples::MOS6502::ISASimulator.new(bus)
            RHDL::Examples::MOS6502::RubyISARunner.new(bus, cpu)
          else
            raise ArgumentError, "Invalid ISA backend #{backend.inspect}. Use :native or :ruby."
          end
        end

        def normalize_isa_backend(backend)
          case backend
          when :native, :ruby
            backend
          else
            raise ArgumentError, "Invalid backend #{backend.inspect} for :isa mode. Use :native or :ruby."
          end
        end

        def normalize_ruby_backend(backend)
          return backend if backend == :ruby
          raise ArgumentError, "Invalid backend #{backend.inspect} for :ruby mode. Use :ruby."
        end

        def normalize_ir_backend(backend)
          case backend
          when :interpret, :jit, :compile
            backend
          else
            raise ArgumentError, "Invalid backend #{backend.inspect} for :ir mode. Use :interpret, :jit, or :compile."
          end
        end

        def default_backend(mode)
          case mode
          when :isa
            RHDL::Examples::MOS6502::NATIVE_AVAILABLE ? :native : :ruby
          when :ruby
            :ruby
          when :ir
            :compile
          when :netlist
            :compile
          when :verilog
            nil
          else
            raise "Unknown mode: #{mode}. Valid modes: isa, ruby, ir, netlist, verilog"
          end
        end
      end
    end
  end
end
