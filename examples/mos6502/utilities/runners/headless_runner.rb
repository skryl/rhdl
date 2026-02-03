# frozen_string_literal: true

# Headless runner factory for MOS6502 emulation
# Creates runners for testing without terminal UI
#
# This provides the same runner creation logic as Apple2Terminal
# but without any terminal/display dependencies.

require_relative '../apple2/harness'
require_relative 'isa_runner'

module MOS6502
  class HeadlessRunner
    attr_reader :runner, :mode, :sim_backend

    # Create a headless runner with the specified options
    # @param mode [Symbol] Simulation mode: :isa, :hdl, :netlist, :verilog
    # @param sim [Symbol] Simulator backend: :interpret, :jit, :compile (for hdl/netlist modes)
    def initialize(mode: :isa, sim: :jit)
      @mode = mode
      @sim_backend = sim

      # Create runner based on mode and sim backend
      @runner = case mode
                when :isa
                  # ISA mode ignores --sim option
                  Apple2Harness::ISARunner.new
                when :hdl
                  # HDL mode uses IR-based simulators
                  require_relative 'ir_runner'
                  IRSimulatorRunner.new(sim)
                when :netlist
                  raise "Netlist mode not yet implemented for MOS6502"
                when :verilog
                  require_relative 'verilator_runner'
                  RHDL::MOS6502::VerilatorRunner.new
                else
                  raise "Unknown mode: #{mode}. Valid modes: isa, hdl, netlist, verilog"
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

    # Get backend (for IR-based simulators)
    def backend
      case @mode
      when :isa
        nil
      when :hdl
        @sim_backend
      when :netlist
        @sim_backend
      when :verilog
        nil
      end
    end

    # Get memory sample for verification
    def memory_sample
      # Use read_memory if available (handles native vs non-native mode)
      # Otherwise fall back to bus.read
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
      # Simple "Hello" display program that writes to text page
      # Start address: $0800
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
    def self.with_demo(mode: :isa, sim: :jit)
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
    def self.with_karateka(mode: :isa, sim: :jit)
      raise "Karateka ROM not found at #{KARATEKA_ROM_PATH}" unless File.exist?(KARATEKA_ROM_PATH)
      raise "Karateka memory dump not found at #{KARATEKA_MEM_PATH}" unless File.exist?(KARATEKA_MEM_PATH)

      runner = new(mode: mode, sim: sim)

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
  end
end
