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
  end
end
