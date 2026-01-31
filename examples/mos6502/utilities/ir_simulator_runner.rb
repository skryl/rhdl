# frozen_string_literal: true

# Wrapper for IR-based simulators (HDL mode with interpret/jit/compile backends)
# Provides a unified interface for different simulation backends
# Uses MOS6502::CPU IR with internalized memory in Rust (or Ruby fallback)
class IRSimulatorRunner
  attr_reader :bus, :sim

  def initialize(sim_backend = :interpret)
    require 'rhdl/codegen'
    require_relative '../hdl/cpu'

    @bus = MOS6502::Apple2Bus.new("apple2_bus")
    @sim_backend = sim_backend
    @sim = nil
    @cycles = 0
    @halted = false
    @use_rust_memory = false  # Will be set true if Rust MOS6502 mode available
    @last_speaker_sync_time = nil

    # Generate IR JSON from MOS6502::CPU component
    ir = MOS6502::CPU.to_flat_ir
    @ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)
  end

  def create_simulator
    sim = case @sim_backend
    when :interpret
      # IrInterpreterWrapper has built-in Ruby fallback if native extension unavailable
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

    # Check if Rust MOS6502 mode is available
    @use_rust_memory = sim.respond_to?(:mos6502_mode?) && sim.mos6502_mode?

    # Cache clock signal and list indices for proper edge detection in clock_tick
    # Only needed when using Ruby memory bridging (not @use_rust_memory)
    if sim.respond_to?(:get_signal_idx) && sim.respond_to?(:get_clock_list_idx)
      clk_sig_idx = sim.get_signal_idx('clk')
      @clk_list_idx = clk_sig_idx ? sim.get_clock_list_idx(clk_sig_idx) : -1
    else
      @clk_list_idx = -1
    end

    sim
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

    if @use_rust_memory
      # Load directly into Rust memory (rom = true for ROM protection)
      @sim.mos6502_load_memory(bytes_array, base_addr, true)
    end

    # Also load into Ruby bus (for screen reading, etc.)
    @bus.load_rom(bytes_array, base_addr: base_addr)
  end

  def load_ram(bytes, base_addr:)
    @sim ||= create_simulator
    bytes_array = bytes.is_a?(String) ? bytes.bytes : bytes

    if @use_rust_memory
      # Load directly into Rust memory (rom = false for RAM)
      @sim.mos6502_load_memory(bytes_array, base_addr, false)
    end

    # Also load into Ruby bus (for screen reading, etc.)
    @bus.load_ram(bytes_array, base_addr: base_addr)
  end

  def load_disk(path_or_bytes, drive: 0)
    @bus.load_disk(path_or_bytes, drive: drive)
  end

  def disk_loaded?(drive: 0)
    @bus.disk_loaded?(drive: drive)
  end

  # Set reset vector directly (bypasses ROM protection)
  # This is needed for tests that want to start at a specific address
  def set_reset_vector(addr)
    @sim ||= create_simulator

    if @use_rust_memory
      # Set in Rust memory
      @sim.mos6502_set_reset_vector(addr)
    end

    # Also set in Ruby bus memory (bypassing ROM protection)
    memory = @bus.instance_variable_get(:@memory)
    memory[0xFFFC] = addr & 0xFF
    memory[0xFFFD] = (addr >> 8) & 0xFF
  end

  def reset
    @sim ||= create_simulator
    # Pulse reset - matches harness.rb exactly
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
    clock_tick  # 1 cycle with rst=1
    @sim.poke('rst', 0)

    # Need 5 more cycles for reset_step to reach 5 and state to transition to FETCH
    # (matches harness.rb: "5.times { clock_cycle(rst: 0) }")
    5.times { clock_tick }

    # Now CPU is in STATE_FETCH. Load PC with reset vector value.
    if @use_rust_memory
      lo = @sim.mos6502_read_memory(0xFFFC)
      hi = @sim.mos6502_read_memory(0xFFFD)
    else
      lo = @bus.read(0xFFFC)
      hi = @bus.read(0xFFFD)
    end
    target_addr = (hi << 8) | lo

    # Get the opcode at target address - we'll need this for IR loading
    if @use_rust_memory
      opcode = @sim.mos6502_read_memory(target_addr)
    else
      opcode = @bus.read(target_addr)
    end

    # Set PC to target address and provide opcode on data_in
    # This matches harness.rb ext_pc_load sequence exactly
    @sim.poke('ext_pc_load_data', target_addr)
    @sim.poke('ext_pc_load_en', 1)
    @sim.poke('data_in', opcode)

    # Clock cycle to load PC and IR (matches harness low/high phase)
    @sim.poke('clk', 0)
    @sim.evaluate  # Combinational only (low phase)
    @sim.poke('clk', 1)
    @sim.tick      # Registers capture (high phase)

    # Clear external load enable (matches harness clear_ext_loads)
    @sim.poke('ext_pc_load_en', 0)

    # After this: PC=target_addr, ready to execute first instruction
    # Do NOT run extra cycles - harness.rb doesn't either
    @cycles = 0
    @halted = false
  end

  def run_steps(steps)
    @sim ||= create_simulator

    if @use_rust_memory
      # Use batched Rust execution - no Ruby FFI per cycle!
      return if @halted

      cycles_run = @sim.mos6502_run_cycles(steps)
      @cycles += cycles_run

      # Sync screen memory from Rust memory to Ruby bus for screen reading
      sync_screen_memory_from_rust

      # Check halted state
      @halted = @sim.peek('halted') == 1
    else
      # Fallback: Ruby memory bridging (slow but works without native extension)
      steps.times do
        break if @halted
        clock_tick
        @cycles += 1
        @halted = @sim.peek('halted') == 1
      end
    end
  end

  # Execute one complete instruction and return the number of cycles it took.
  # This matches ISA simulator's step() method.
  # Detects instruction completion by monitoring state transitions to FETCH.
  # @param sync_screen [Boolean] Whether to sync screen memory after (default: false for perf)
  # @return [Integer] The number of cycles the instruction took
  def step_instruction(sync_screen: false)
    @sim ||= create_simulator
    return 0 if @halted

    state_fetch = 1  # STATE_FETCH constant from CPU
    cycles = 0
    max_cycles = 20  # Safety limit (longest 6502 instruction is 7 cycles)

    # Get initial state
    prev_state = @sim.peek('state')

    loop do
      # Run one clock cycle
      if @use_rust_memory
        @sim.mos6502_run_cycles(1)
      else
        clock_tick
      end
      cycles += 1
      @cycles += 1
      @halted = @sim.peek('halted') == 1

      state = @sim.peek('state')

      # Instruction is complete when we transition TO FETCH from another state
      # (not when we're already in FETCH from the start)
      if state == state_fetch && prev_state != state_fetch
        break
      end

      prev_state = state
      break if cycles >= max_cycles || @halted
    end

    # Only sync screen memory if explicitly requested (expensive operation)
    sync_screen_memory_from_rust if sync_screen && @use_rust_memory

    cycles
  end

  # Run complete instructions until target_cycles have elapsed.
  # This matches ISA simulator's run_cycles semantics exactly.
  # May overshoot target_cycles by completing the current instruction.
  # @param target_cycles [Integer] The minimum number of cycles to run
  # @return [Integer] The actual number of cycles run
  def run_cycles(target_cycles)
    @sim ||= create_simulator
    return 0 if @halted

    cycles_run = 0

    while cycles_run < target_cycles && !@halted
      instruction_cycles = step_instruction
      cycles_run += instruction_cycles
    end

    cycles_run
  end

  # Run one clock cycle with memory bridging
  # Timing matches the Rust run_mos6502_cycles implementation:
  # 1. Clock falling edge - combinational logic updates (addr becomes valid)
  # 2. Sample address and do memory bridging
  # 3. Clock rising edge - registers capture values
  #
  # IMPORTANT: Uses Rust memory when @use_rust_memory is true, otherwise Ruby bus.
  # This ensures memory isolation when running with Rust-based IR simulators.
  def clock_tick
    # Clock falling edge - ONLY combinational logic (no DFF update!)
    @sim.poke('clk', 0)
    @sim.evaluate  # Use evaluate, not tick - tick would update DFFs prematurely

    # NOW get address and read/write signal from CPU (reflects current state)
    addr = @sim.peek('addr')
    rw = @sim.peek('rw')

    if rw == 1
      # Read: get data and provide to CPU
      if @use_rust_memory
        data = @sim.mos6502_read_memory(addr)
      else
        data = @bus.read(addr)
      end
      @sim.poke('data_in', data)
    else
      # Write: get data from CPU and write to memory
      data = @sim.peek('data_out')
      if @use_rust_memory
        @sim.mos6502_write_memory(addr, data)
      else
        @bus.write(addr, data)
      end
    end

    # Set prev_clock to 0 so tick() detects rising edge (0->1)
    # This is needed because tick() uses prev_clock_values for edge detection
    if @clk_list_idx && @clk_list_idx >= 0 && @sim.respond_to?(:set_prev_clock)
      @sim.set_prev_clock(@clk_list_idx, 0)
    end

    # Clock rising edge - registers capture values (DFFs update here)
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

  # Sync speaker toggles from Rust backend to Ruby speaker for audio generation
  # Called each frame by the emulator main loop
  def sync_speaker_state
    return unless @use_rust_memory
    return unless @sim.respond_to?(:mos6502_speaker_toggles)

    current_toggles = @sim.mos6502_speaker_toggles
    return if current_toggles == 0

    # Calculate elapsed time since last sync for timing estimation
    now = Time.now
    elapsed = @last_speaker_sync_time ? (now - @last_speaker_sync_time) : 0.016  # Default ~60fps
    @last_speaker_sync_time = now

    # Forward toggles to speaker with timing info for proper audio generation
    @bus.speaker.sync_toggles(current_toggles, elapsed)

    # Reset the Rust toggle counter
    @sim.mos6502_reset_speaker_toggles
  end

  private

  # Sync screen memory from Rust memory to Ruby bus
  # This allows screen reading to work even when using Rust memory
  # Syncs: text page 1, HiRes page 1, HiRes page 2
  def sync_screen_memory_from_rust
    return unless @use_rust_memory

    # Get direct access to bus memory for faster writes
    memory = @bus.instance_variable_get(:@memory)

    # Text page 1: $0400-$07FF (1024 bytes)
    (0...1024).each do |i|
      memory[0x0400 + i] = @sim.mos6502_read_memory(0x0400 + i)
    end

    # HiRes page 1: $2000-$3FFF (8192 bytes)
    (0...8192).each do |i|
      memory[0x2000 + i] = @sim.mos6502_read_memory(0x2000 + i)
    end

    # HiRes page 2: $4000-$5FFF (8192 bytes)
    (0...8192).each do |i|
      memory[0x4000 + i] = @sim.mos6502_read_memory(0x4000 + i)
    end
  end

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
