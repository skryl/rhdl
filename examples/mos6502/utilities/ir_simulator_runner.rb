# frozen_string_literal: true

# Wrapper for IR-based simulators (HDL mode with interpret/jit/compile backends)
# Provides a unified interface for different simulation backends
class IRSimulatorRunner
  attr_reader :bus

  def initialize(sim_backend = :interpret)
    require 'rhdl/codegen'
    require_relative '../../apple2/hdl/apple2'

    @bus = MOS6502::Apple2Bus.new("apple2_bus")
    @sim_backend = sim_backend
    @sim = nil
    @cycles = 0
    @halted = false
    @key_data = 0
    @key_ready = false

    # Generate IR JSON from Apple2 component
    ir = RHDL::Apple2::Apple2.to_flat_ir
    @ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)
  end

  def create_simulator
    case @sim_backend
    when :interpret
      raise "IR Interpreter not available" unless RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
      RHDL::Codegen::IR::IrInterpreterWrapper.new(@ir_json)
    when :jit
      raise "IR JIT not available" unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
      RHDL::Codegen::IR::IrJitWrapper.new(@ir_json)
    when :compile
      raise "IR Compiler not available" unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
      RHDL::Codegen::IR::IrCompilerWrapper.new(@ir_json)
    else
      raise "Unknown IR backend: #{@sim_backend}"
    end
  end

  def native?
    @sim_backend != :interpret
  end

  def simulator_type
    case @sim_backend
    when :interpret then :ir_interpret
    when :jit then :ir_jit
    when :compile then :ir_compile
    end
  end

  def load_rom(bytes, base_addr:)
    @sim ||= create_simulator
    bytes_array = bytes.is_a?(String) ? bytes.bytes : bytes
    @sim.load_rom(bytes_array)
    # Also load into bus for screen reading
    @bus.load_rom(bytes_array, base_addr: base_addr)
  end

  def load_ram(bytes, base_addr:)
    @sim ||= create_simulator
    bytes_array = bytes.is_a?(String) ? bytes.bytes : bytes
    @sim.load_ram(bytes_array, base_addr)
    # Also load into bus for screen reading
    @bus.load_ram(bytes_array, base_addr: base_addr)
  end

  def load_disk(path_or_bytes, drive: 0)
    @bus.load_disk(path_or_bytes, drive: drive)
  end

  def disk_loaded?(drive: 0)
    @bus.disk_loaded?(drive: drive)
  end

  def reset
    @sim ||= create_simulator
    @sim.poke('reset', 1)
    @sim.tick
    @sim.poke('reset', 0)
    @cycles = 0
    @halted = false
  end

  def run_steps(steps)
    @sim ||= create_simulator
    result = @sim.run_cpu_cycles(steps, @key_data, @key_ready)

    # Sync screen from IR simulator RAM to bus
    sync_screen_from_sim if result[:text_dirty]

    if result[:key_cleared]
      @key_ready = false
      @bus.clear_key
    end

    @cycles += result[:cycles_run]
  end

  def sync_screen_from_sim
    # Read text page from IR simulator and write to bus
    text_page = @sim.read_ram(0x0400, 0x0400)  # $0400-$07FF
    text_page.each_with_index do |byte, i|
      @bus.ram[0x0400 + i] = byte
    end
  end

  def inject_key(ascii)
    @key_data = ascii
    @key_ready = true
    @bus.inject_key(ascii)
  end

  def key_ready?
    @key_ready
  end

  def clear_key
    @key_ready = false
    @bus.clear_key
  end

  def read_screen
    @bus.read_text_page_string
  end

  def read_screen_array
    @bus.read_text_page
  end

  def screen_dirty?
    @bus.text_page_dirty?
  end

  def clear_screen_dirty
    @bus.clear_text_page_dirty
  end

  def cpu_state
    @sim ||= create_simulator
    {
      pc: @sim.peek('cpu__pc_reg'),
      a: @sim.peek('cpu__a_reg'),
      x: @sim.peek('cpu__x_reg'),
      y: @sim.peek('cpu__y_reg'),
      sp: @sim.peek('cpu__s_reg'),
      p: @sim.peek('cpu__debug_p'),
      cycles: @cycles,
      halted: @halted,
      simulator_type: simulator_type
    }
  end

  def halted?
    @halted
  end

  def cycle_count
    @cycles
  end

  # Return dry-run information for testing without starting emulation
  # @return [Hash] Information about engine configuration and memory state
  def dry_run_info
    @sim ||= create_simulator
    {
      mode: :hdl,
      simulator_type: simulator_type,
      native: native?,
      backend: @sim_backend,
      cpu_state: cpu_state,
      memory_sample: memory_sample
    }
  end

  private

  # Return a sample of memory for verification
  def memory_sample
    @sim ||= create_simulator
    {
      zero_page: @sim.read_ram(0x0000, 256),
      stack: @sim.read_ram(0x0100, 256),
      text_page: @sim.read_ram(0x0400, 1024),
      program_area: @sim.read_ram(0x0800, 256),
      reset_vector: @sim.read_ram(0xFFFC, 2)
    }
  end
end
