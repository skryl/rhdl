# frozen_string_literal: true

# Wrapper for IR-based simulators (HDL mode with interpret/jit/compile backends)
# Provides a unified interface for different simulation backends
# Uses MOS6502::CPU IR with Apple2Bus for memory/I/O (like ISA simulator)
class IRSimulatorRunner
  attr_reader :bus

  def initialize(sim_backend = :interpret)
    require 'rhdl/codegen'
    require_relative '../hdl/cpu'

    @bus = MOS6502::Apple2Bus.new("apple2_bus")
    @sim_backend = sim_backend
    @sim = nil
    @cycles = 0
    @halted = false

    # Generate IR JSON from MOS6502::CPU component
    ir = MOS6502::CPU.to_flat_ir
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
    @bus.load_rom(bytes_array, base_addr: base_addr)
  end

  def load_ram(bytes, base_addr:)
    @sim ||= create_simulator
    bytes_array = bytes.is_a?(String) ? bytes.bytes : bytes
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
    # Pulse reset
    @sim.poke('rst', 1)
    @sim.poke('rdy', 1)
    @sim.poke('irq', 1)
    @sim.poke('nmi', 1)
    @sim.poke('data_in', 0)
    @sim.poke('ext_pc_load_en', 0)
    @sim.poke('ext_a_load_en', 0)
    @sim.poke('ext_x_load_en', 0)
    @sim.poke('ext_y_load_en', 0)
    @sim.poke('ext_sp_load_en', 0)
    clock_tick
    @sim.poke('rst', 0)
    # Run reset sequence (6 cycles)
    6.times { clock_tick }
    @cycles = 0
    @halted = false
  end

  def run_steps(steps)
    @sim ||= create_simulator
    steps.times do
      break if @halted
      clock_tick
      @cycles += 1
      @halted = @sim.peek('halted') == 1
    end
  end

  # Run one clock cycle with memory bridging
  def clock_tick
    # Get address and read/write signal from CPU
    addr = @sim.peek('addr')
    rw = @sim.peek('rw')

    if rw == 1
      # Read: get data from bus and provide to CPU
      data = @bus.read(addr)
      @sim.poke('data_in', data)
    else
      # Write: get data from CPU and write to bus
      data = @sim.peek('data_out')
      @bus.write(addr, data)
    end

    # Advance clock
    @sim.poke('clk', 0)
    @sim.tick
    @sim.poke('clk', 1)
    @sim.tick
  end

  def inject_key(ascii)
    @bus.inject_key(ascii)
  end

  def key_ready?
    @bus.key_ready
  end

  def clear_key
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
      pc: @sim.peek('reg_pc'),
      a: @sim.peek('reg_a'),
      x: @sim.peek('reg_x'),
      y: @sim.peek('reg_y'),
      sp: @sim.peek('reg_sp'),
      p: @sim.peek('reg_p'),
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
    {
      zero_page: (0...256).map { |i| @bus.read(i) },
      stack: (0...256).map { |i| @bus.read(0x0100 + i) },
      text_page: (0...1024).map { |i| @bus.read(0x0400 + i) },
      program_area: (0...256).map { |i| @bus.read(0x0800 + i) },
      reset_vector: [@bus.read(0xFFFC), @bus.read(0xFFFD)]
    }
  end
end
