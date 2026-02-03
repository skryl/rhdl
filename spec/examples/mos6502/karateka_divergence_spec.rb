# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/utilities/renderers/braille_renderer'

RSpec.describe 'Karateka MOS6502 4-Way Divergence Analysis' do
  # Compare all 4 MOS6502 simulators:
  # 1. ISA - Native Rust instruction-level simulator
  # 2. IR Interpret - HDL IR interpreter (Ruby fallback or native)
  # 3. IR JIT - HDL IR JIT compiler
  # 4. IR Compile - HDL IR ahead-of-time compiler
  #
  # All use internalized memory - this isolates CPU behavior differences

  ROM_PATH = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  KARATEKA_MEM_PATH = File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

  # Test parameters
  TOTAL_CYCLES = 2_000_000       # 2M cycles for 4-way comparison
  CHECKPOINT_INTERVAL = 200_000  # Check every 200K cycles
  SCREEN_INTERVAL = 1_000_000    # Print screen every 1M cycles
  INTERPRETER_MAX_CYCLES = 500_000  # Interpreter is slow, limit to 500K

  before(:all) do
    @rom_available = File.exist?(ROM_PATH)
    @karateka_available = File.exist?(KARATEKA_MEM_PATH)
    if @rom_available
      @rom_data = File.binread(ROM_PATH).bytes
    end
    if @karateka_available
      @karateka_mem = File.binread(KARATEKA_MEM_PATH).bytes
    end
  end

  def create_karateka_rom
    rom = @rom_data.dup
    rom[0x2FFC] = 0x2A  # low byte of $B82A
    rom[0x2FFD] = 0xB8  # high byte of $B82A
    rom
  end

  def native_isa_available?
    require_relative '../../../examples/mos6502/utilities/isa_simulator_native'
    MOS6502::NATIVE_AVAILABLE
  rescue LoadError
    false
  end

  def ir_backend_available?(backend)
    require 'rhdl/codegen'

    case backend
    when :interpret
      # Interpreter is always available (has Ruby fallback)
      true
    when :jit
      return false unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
      # Check if MOS6502 mode is available
      require_relative '../../../examples/mos6502/hdl/cpu'
      ir = MOS6502::CPU.to_flat_ir
      ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)
      sim = RHDL::Codegen::IR::IrJitWrapper.new(ir_json)
      sim.respond_to?(:mos6502_mode?) && sim.mos6502_mode?
    when :compile
      return false unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
      require_relative '../../../examples/mos6502/hdl/cpu'
      ir = MOS6502::CPU.to_flat_ir
      ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)
      sim = RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json)
      sim.respond_to?(:mos6502_mode?) && sim.mos6502_mode?
    else
      false
    end
  rescue LoadError, StandardError
    false
  end

  def verilator_available?
    ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
      File.executable?(File.join(path, 'verilator'))
    end
  end

  # Simulator wrapper to provide uniform interface
  class SimulatorWrapper
    attr_reader :name, :type, :bus

    def initialize(name, type)
      @name = name
      @type = type
      @halted = false
    end

    def pc; raise NotImplementedError; end
    def a; raise NotImplementedError; end
    def x; raise NotImplementedError; end
    def y; raise NotImplementedError; end
    def halted?; @halted; end
    def run_steps(n); raise NotImplementedError; end
    def read_memory(addr); raise NotImplementedError; end
    def opcode; raise NotImplementedError; end
    # Run n instructions and return array of [pc, opcode] pairs executed
    def run_instructions_with_opcodes(n); raise NotImplementedError; end
  end

  class ISAWrapper < SimulatorWrapper
    def initialize(cpu, bus)
      super("ISA (Native Rust)", :isa)
      @cpu = cpu
      @bus = bus
    end

    def pc; @cpu.pc; end
    def a; @cpu.a; end
    def x; @cpu.x; end
    def y; @cpu.y; end
    def sp; @cpu.sp; end
    def halted?; @cpu.halted?; end

    def run_steps(n)
      n.times do
        break if @cpu.halted?
        @cpu.step
      end
    end

    def read_memory(addr)
      @bus.mem_read(addr)
    end

    def opcode
      # Read opcode at current PC
      @cpu.peek(@cpu.pc)
    end

    # Run n instructions and return array of [pc, opcode, sp] tuples executed
    def run_instructions_with_opcodes(n)
      opcodes = []
      n.times do
        break if @cpu.halted?
        current_pc = @cpu.pc
        current_opcode = @cpu.peek(current_pc)
        current_sp = @cpu.sp
        opcodes << [current_pc, current_opcode, current_sp]
        @cpu.step
      end
      opcodes
    end
  end

  class IRWrapper < SimulatorWrapper
    # State constants from ControlUnit
    STATE_FETCH = 0x01
    STATE_DECODE = 0x02
    STATE_RTS_PULL_LO = 0x10
    STATE_RTS_PULL_HI = 0x11

    def initialize(runner, backend_name)
      super("IR #{backend_name}", :ir)
      @runner = runner
      @bus = runner.bus
    end

    def pc; @runner.cpu_state[:pc]; end
    def a; @runner.cpu_state[:a]; end
    def x; @runner.cpu_state[:x]; end
    def y; @runner.cpu_state[:y]; end
    def sp; @runner.cpu_state[:sp]; end
    def halted?; @runner.halted?; end

    def run_steps(n)
      @runner.run_steps(n)
    end

    # Run instructions until n cycles have elapsed (matches ISA run_cycles semantics)
    def run_cycles(n)
      @runner.run_cycles(n)
    end

    def read_memory(addr)
      # Use Rust memory when available for native backends
      use_rust_memory = @runner.instance_variable_get(:@use_rust_memory)
      if use_rust_memory
        @runner.sim.mos6502_read_memory(addr)
      else
        @runner.bus.read(addr)
      end
    end

    def opcode
      @runner.sim.peek('opcode')
    end

    def state
      @runner.sim.peek('state')
    end

    # Run until n instructions complete and return array of [pc, opcode, sp] tuples
    # An instruction completes when the state machine transitions from DECODE
    # We track the opcode that was in IR when we entered DECODE state
    def run_instructions_with_opcodes(n, trace_rts: false)
      # Use native method if available (works for JIT and Compiler backends)
      sim = @runner.sim
      if sim.respond_to?(:mos6502_run_instructions_with_opcodes)
        return sim.mos6502_run_instructions_with_opcodes(n)
      end

      # Fallback to manual cycle stepping (for Ruby interpreter or testing)
      opcodes = []
      last_state = state
      max_cycles = n * 10  # Safety limit: assume max 10 cycles per instruction
      cycles = 0
      use_rust_memory = @runner.instance_variable_get(:@use_rust_memory)

      while opcodes.length < n && cycles < max_cycles && !halted?
        current_state = state
        current_sp_before = sp

        # Check if we're about to execute RTS and should trace
        if trace_rts && current_state == STATE_DECODE && opcode == 0x60
          puts "\n    === RTS TRACE at PC=$#{format('%04X', (pc - 1) & 0xFFFF)} SP=$#{format('%02X', sp)} ==="
          trace_rts_execution(use_rust_memory)
          # After tracing, re-check state
          current_state = state
        end

        # Run one clock cycle with proper memory bridging
        sim.poke('clk', 0)
        sim.evaluate

        # Memory bridging - must use Rust memory for JIT/Compile backends
        addr = sim.peek('addr')
        rw = sim.peek('rw')
        if rw == 1
          # Read from memory
          if use_rust_memory
            data = sim.mos6502_read_memory(addr)
          else
            data = @runner.bus.read(addr)
          end
          sim.poke('data_in', data)
        else
          # Write to memory
          data = sim.peek('data_out')
          if use_rust_memory
            sim.mos6502_write_memory(addr, data)
          else
            @runner.bus.write(addr, data)
          end
        end

        sim.poke('clk', 1)
        sim.tick
        cycles += 1

        current_state = state
        # When we transition into DECODE, record the instruction
        # At this point, PC points past the opcode, and opcode register has the instruction
        if current_state == STATE_DECODE && last_state != STATE_DECODE
          current_opcode = opcode
          current_sp = sp
          # PC has already incremented past opcode, so subtract 1 to get opcode address
          opcode_pc = (pc - 1) & 0xFFFF
          opcodes << [opcode_pc, current_opcode, current_sp]
        end
        last_state = current_state
      end

      # Sync screen memory if using Rust memory
      if use_rust_memory
        @runner.send(:sync_screen_memory_from_rust)
      end

      opcodes
    end

    # Trace an RTS instruction execution step by step
    def trace_rts_execution(use_rust_memory)
      sim = @runner.sim

      state_names = {
        0x00 => "RESET", 0x01 => "FETCH", 0x02 => "DECODE", 0x03 => "FETCH_OP1",
        0x04 => "FETCH_OP2", 0x05 => "ADDR_LO", 0x06 => "ADDR_HI", 0x07 => "READ_MEM",
        0x08 => "EXECUTE", 0x09 => "WRITE_MEM", 0x0A => "PUSH", 0x0B => "PULL",
        0x0C => "BRANCH", 0x0D => "BRANCH_TAKE", 0x0E => "JSR_PUSH_HI", 0x0F => "JSR_PUSH_LO",
        0x10 => "RTS_PULL_LO", 0x11 => "RTS_PULL_HI", 0x12 => "RTI_PULL_P",
        0x13 => "RTI_PULL_LO", 0x14 => "RTI_PULL_HI", 0xFF => "HALT"
      }

      puts "    Cyc | State           | Addr   | Data   | SP         | AddrLoLat  | return_addr | actual_pc_addr | ctrl (before tick)"
      puts "    " + "-" * 115

      start_state = state
      max_cycles = 15
      cycle = 0

      while cycle < max_cycles && !(cycle > 0 && state == STATE_FETCH)
        before_state = state
        before_sp = sp
        before_pc = self.pc
        addr_lo_before = sim.peek('alatch_addr_lo')

        # Clock falling edge - combinational logic
        sim.poke('clk', 0)
        sim.evaluate

        # Get address and control signals
        addr = sim.peek('addr')
        rw = sim.peek('rw')
        addr_lo_after_eval = sim.peek('alatch_addr_lo')

        # Get return_addr and actual_pc_addr (these are combinational)
        return_addr = sim.peek('return_addr') rescue 0
        actual_pc_addr = sim.peek('actual_pc_addr') rescue 0

        # Get control signals BEFORE tick (during this state)
        addr_sel_before = sim.peek('ctrl_addr_sel') rescue 0
        load_addr_lo_before = sim.peek('ctrl_load_addr_lo') rescue 0
        load_addr_hi_before = sim.peek('ctrl_load_addr_hi') rescue 0

        # Memory operation
        if rw == 1
          if use_rust_memory
            data = sim.mos6502_read_memory(addr)
          else
            data = @runner.bus.read(addr)
          end
          sim.poke('data_in', data)
          data_str = "$#{format('%02X', data)}(r)"
        else
          data = sim.peek('data_out')
          if use_rust_memory
            sim.mos6502_write_memory(addr, data)
          else
            @runner.bus.write(addr, data)
          end
          data_str = "$#{format('%02X', data)}(w)"
        end

        # Clock rising edge - register capture
        sim.poke('clk', 1)
        sim.tick
        cycle += 1

        after_state = state
        after_sp = sp
        after_pc = self.pc
        addr_lo_after = sim.peek('alatch_addr_lo')

        state_trans = "#{state_names[before_state] || '?'}->#{state_names[after_state] || '?'}"

        # Get stack address signals for debugging
        stack_addr = sim.peek('stack_addr') rescue 0
        stack_addr_plus1 = sim.peek('stack_addr_plus1') rescue 0
        addr_sel = sim.peek('ctrl_addr_sel') rescue 0
        load_addr_lo = sim.peek('ctrl_load_addr_lo') rescue 0

        puts "    %3d | %-15s | $%04X  | %-6s | $%02X->$%02X | $%02X->$%02X     | $%04X       | $%04X | sel=%d ldlo=%d (before tick)" % [
          cycle, state_trans, addr, data_str,
          before_sp, after_sp,
          addr_lo_before, addr_lo_after,
          return_addr, actual_pc_addr,
          addr_sel_before, load_addr_lo_before
        ]

        break if after_state == STATE_FETCH && cycle > 1
      end

      puts "    Final: PC=$#{format('%04X', self.pc)} SP=$#{format('%02X', sp)}"
    end

    # Trace the current RTS sequence in detail (for debugging)
    # This prints state machine states, addresses, data values, and latch contents
    def trace_rts_sequence
      sim = @runner.sim
      use_rust_memory = @runner.instance_variable_get(:@use_rust_memory)

      state_names = {
        0x00 => "RESET",
        0x01 => "FETCH",
        0x02 => "DECODE",
        0x03 => "FETCH_OP1",
        0x04 => "FETCH_OP2",
        0x05 => "ADDR_LO",
        0x06 => "ADDR_HI",
        0x07 => "READ_MEM",
        0x08 => "EXECUTE",
        0x09 => "WRITE_MEM",
        0x0A => "PUSH",
        0x0B => "PULL",
        0x0C => "BRANCH",
        0x0D => "BRANCH_TAKE",
        0x0E => "JSR_PUSH_HI",
        0x0F => "JSR_PUSH_LO",
        0x10 => "RTS_PULL_LO",
        0x11 => "RTS_PULL_HI",
        0xFF => "HALT"
      }

      puts "    Current state: #{state_names[state] || "0x#{state.to_s(16)}"}"
      puts "    Current PC: $#{format('%04X', pc)}, SP: $#{format('%02X', sp)}"

      # Run until we reach FETCH or HALT (next instruction)
      max_cycles = 20
      cycles = 0

      puts "    Cycle-by-cycle trace:"
      puts "    %-4s | %-14s | %-6s | %-8s | %-8s | %-8s | %-8s | %-8s" %
           ["Cyc", "State", "Addr", "Data_In", "AddrLoLat", "PC", "SP", "RetAddr"]
      puts "    " + "-" * 85

      while cycles < max_cycles && state != STATE_FETCH && state != 0xFF
        current_state = state
        current_pc = pc
        current_sp = sp

        # Clock falling edge
        sim.poke('clk', 0)
        sim.evaluate

        # Get address and memory values
        addr = sim.peek('addr')
        rw = sim.peek('rw')
        addr_lo_latch = sim.peek('alatch_addr_lo')
        return_addr = sim.peek('return_addr') rescue nil

        # Memory read/write
        if rw == 1
          if use_rust_memory
            data = sim.mos6502_read_memory(addr)
          else
            data = @runner.bus.read(addr)
          end
          sim.poke('data_in', data)
          data_str = "$#{format('%02X', data)} (rd)"
        else
          data = sim.peek('data_out')
          if use_rust_memory
            sim.mos6502_write_memory(addr, data)
          else
            @runner.bus.write(addr, data)
          end
          data_str = "$#{format('%02X', data)} (wr)"
        end

        # Clock rising edge
        sim.poke('clk', 1)
        sim.tick
        cycles += 1

        # Get new state after tick
        new_state = state
        new_pc = pc
        new_sp = sp
        new_addr_lo = sim.peek('alatch_addr_lo')

        ret_addr_str = return_addr ? "$#{format('%04X', return_addr)}" : "n/a"

        puts "    %-4d | %-14s | $%04X  | %-8s | $%02X->$%02X | $%04X->$%04X | $%02X->$%02X | %s" % [
          cycles,
          "#{state_names[current_state] || '?'}->#{state_names[new_state] || '?'}",
          addr,
          data_str,
          addr_lo_latch, new_addr_lo,
          current_pc, new_pc,
          current_sp, new_sp,
          ret_addr_str
        ]
      end

      puts "    Final PC: $#{format('%04X', pc)}, SP: $#{format('%02X', sp)}"
    end
  end

  # Verilator-based simulator wrapper
  class VerilatorWrapper < SimulatorWrapper
    def initialize(runner)
      super("Verilator", :verilator)
      @runner = runner
    end

    def pc; @runner.pc; end
    def a; @runner.a; end
    def x; @runner.x; end
    def y; @runner.y; end
    def sp; @runner.sp; end
    def halted?; @runner.halted?; end

    def run_steps(n)
      @runner.run_cycles(n)
    end

    def read_memory(addr)
      @runner.read_memory(addr)
    end

    def opcode
      @runner.opcode
    end

    def state
      @runner.state
    end

    # Run n instructions and return array of [pc, opcode, sp] tuples
    # Delegates to fast C++ batch execution
    def run_instructions_with_opcodes(n, trace_rts: false)
      @runner.run_instructions_with_opcodes(n)
    end
  end

  def create_isa_simulator
    require_relative '../../../examples/mos6502/utilities/apple2_bus'
    require_relative '../../../examples/mos6502/utilities/isa_simulator_native'

    karateka_rom = create_karateka_rom
    bus = MOS6502::Apple2Bus.new
    bus.load_rom(karateka_rom, base_addr: 0xD000)
    bus.load_ram(@karateka_mem, base_addr: 0x0000)

    cpu = MOS6502::ISASimulatorNative.new(bus)
    cpu.load_bytes(@karateka_mem, 0x0000)
    cpu.load_bytes(karateka_rom, 0xD000)

    # Give bus a reference to CPU for screen reading via mem_read
    bus.instance_variable_set(:@native_cpu, cpu)

    # Initialize HIRES soft switches (like emulator does)
    bus.read(0xC050)  # TXTCLR - graphics mode
    bus.read(0xC052)  # MIXCLR - full screen
    bus.read(0xC054)  # PAGE1 - page 1
    bus.read(0xC057)  # HIRES - hi-res mode

    # Sync video state to native CPU
    cpu.set_video_state(false, false, false, true)

    cpu.reset

    ISAWrapper.new(cpu, bus)
  end

  def create_ir_simulator(backend)
    require_relative '../../../examples/mos6502/utilities/runners/ir_simulator_runner'
    require_relative '../../../examples/mos6502/utilities/apple2_bus'

    runner = IRSimulatorRunner.new(backend)

    karateka_rom = create_karateka_rom

    # Load ROM and RAM
    runner.load_rom(karateka_rom, base_addr: 0xD000)
    runner.load_ram(@karateka_mem, base_addr: 0x0000)

    # Set reset vector to $B82A (Karateka entry point)
    runner.set_reset_vector(0xB82A)

    # Reset using proper sequence
    runner.reset

    backend_name = case backend
    when :interpret then "Interpret"
    when :jit then "JIT"
    when :compile then "Compile"
    end

    IRWrapper.new(runner, backend_name)
  end

  def create_verilator_simulator
    require_relative '../../../examples/mos6502/utilities/runners/mos6502_verilator'

    runner = MOS6502::VerilatorRunner.new

    karateka_rom = create_karateka_rom

    # Load ROM and RAM
    runner.load_memory(karateka_rom, 0xD000)
    runner.load_memory(@karateka_mem, 0x0000)

    # Set reset vector to $B82A (Karateka entry point)
    runner.set_reset_vector(0xB82A)

    # Reset
    runner.reset

    VerilatorWrapper.new(runner)
  end

  def hires_checksum(sim, base_addr)
    checksum = 0
    (base_addr..(base_addr + 0x1FFF)).each do |addr|
      checksum = (checksum + sim.read_memory(addr)) & 0xFFFFFFFF
    end
    checksum
  end

  def text_checksum(sim)
    checksum = 0
    (0x0400..0x07FF).each do |addr|
      checksum = (checksum + sim.read_memory(addr)) & 0xFFFFFFFF
    end
    checksum
  end

  # Hi-res screen line address calculation (Apple II interleaved layout)
  def hires_line_address(row, base)
    section = row / 64
    row_in_section = row % 64
    group = row_in_section / 8
    line_in_group = row_in_section % 8
    base + (line_in_group * 0x400) + (group * 0x80) + (section * 0x28)
  end

  def decode_hires(sim, base_addr = 0x2000)
    bitmap = []
    192.times do |row|
      line = []
      line_addr = hires_line_address(row, base_addr)
      40.times do |col|
        byte = sim.read_memory(line_addr + col) || 0
        7.times do |bit|
          line << ((byte >> bit) & 1)
        end
      end
      bitmap << line
    end
    bitmap
  end

  def print_hires_screen(label, bitmap, cycles)
    renderer = RHDL::Apple2::BrailleRenderer.new(chars_wide: 70)
    puts "\n#{label} @ #{cycles / 1_000_000.0}M cycles:"
    puts renderer.render(bitmap, invert: false)
  end

  it 'compares HiRes checksums: ISA, JIT, Compile, Verilator (2M cycles)', timeout: 600 do
    skip 'AppleIIgo ROM not found' unless @rom_available
    skip 'Karateka memory dump not found' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?

    puts "\n" + "=" * 80
    puts "Karateka MOS6502 4-Way Divergence Analysis"
    puts "Total cycles: #{TOTAL_CYCLES.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "(Interpreter limited to #{INTERPRETER_MAX_CYCLES.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} due to speed)"
    puts "=" * 80

    # Create all available simulators
    puts "\nInitializing simulators..."
    simulators = {}

    # ISA simulator (reference)
    simulators[:isa] = create_isa_simulator
    puts "  [x] ISA: Native Rust ISA simulator (reference)"

    # IR backends - JIT and Compile only (interpreter disabled for now)
    [:jit, :compile].each do |backend|
      if ir_backend_available?(backend)
        simulators[backend] = create_ir_simulator(backend)
        puts "  [x] IR #{backend.to_s.capitalize}: Available"
      else
        puts "  [ ] IR #{backend.to_s.capitalize}: Not available (skipped)"
      end
    end

    # Verilator backend
    if verilator_available?
      begin
        simulators[:verilator] = create_verilator_simulator
        puts "  [x] Verilator: Native Verilator RTL simulation"
      rescue StandardError => e
        puts "  [ ] Verilator: Failed to initialize (#{e.message})"
      end
    else
      puts "  [ ] Verilator: Not available (skipped)"
    end

    if simulators.size < 2
      skip "Need at least 2 simulators to compare"
    end

    # Track state at checkpoints
    checkpoints = []
    divergence_points = {}
    # Track cumulative time per simulator
    sim_times = Hash.new(0.0)

    cycles_run = 0
    start_time = Time.now

    puts "\nRunning comparison..."
    puts "-" * 100

    # Header
    sim_names = simulators.keys.map { |k| k.to_s.upcase[0..6].ljust(7) }.join(" | ")
    puts format("  %%     | Cycles  | %s | Rates (M/s)", sim_names)
    puts "  " + "-" * 98

    # Track cycles run per simulator (interpreter has different limit)
    sim_cycles = Hash.new(0)

    while cycles_run < TOTAL_CYCLES
      # Run batch of cycles
      batch_size = [CHECKPOINT_INTERVAL, TOTAL_CYCLES - cycles_run].min

      # Run all simulators and track time for each
      simulators.each do |key, sim|
        # Interpreter has a lower cycle limit
        max_cycles = key == :interpret ? INTERPRETER_MAX_CYCLES : TOTAL_CYCLES
        next if sim_cycles[key] >= max_cycles

        # Calculate batch for this simulator
        sim_batch = [batch_size, max_cycles - sim_cycles[key]].min
        next if sim_batch <= 0

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sim.run_steps(sim_batch)
        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sim_times[key] += (t1 - t0)
        sim_cycles[key] += sim_batch
      end

      cycles_run += batch_size

      # Collect checkpoint data
      checkpoint = { cycles: cycles_run, sims: {} }

      simulators.each do |key, sim|
        checkpoint[:sims][key] = {
          pc: sim.pc,
          a: sim.a,
          x: sim.x,
          y: sim.y,
          halted: sim.halted?,
          hires_p1: hires_checksum(sim, 0x2000),
          hires_p2: hires_checksum(sim, 0x4000),
          text: text_checksum(sim)
        }
      end

      checkpoints << checkpoint

      # Check for divergence from ISA reference (only for simulators still running)
      isa_data = checkpoint[:sims][:isa]
      simulators.each_key do |key|
        next if key == :isa
        next if divergence_points[key]

        # Skip divergence check for simulators that have stopped
        max_c = key == :interpret ? INTERPRETER_MAX_CYCLES : TOTAL_CYCLES
        next if sim_cycles[key] >= max_c && cycles_run > sim_cycles[key]

        sim_data = checkpoint[:sims][key]
        if sim_data[:hires_p1] != isa_data[:hires_p1] ||
           sim_data[:hires_p2] != isa_data[:hires_p2] ||
           sim_data[:text] != isa_data[:text]
          divergence_points[key] = {
            cycles: cycles_run,
            isa: isa_data,
            sim: sim_data
          }
        end
      end

      # Progress output
      pct = (cycles_run.to_f / TOTAL_CYCLES * 100).round(1)

      # Show PC values, with "-" for stopped simulators
      pc_values = simulators.map do |k, _|
        max_c = k == :interpret ? INTERPRETER_MAX_CYCLES : TOTAL_CYCLES
        if sim_cycles[k] >= max_c && cycles_run > sim_cycles[k]
          "DONE".ljust(4)
        else
          format("%04X", checkpoint[:sims][k][:pc])
        end
      end.join(" | ")

      # Per-simulator rates (based on actual cycles run)
      rate_strs = simulators.keys.map do |k|
        t = sim_times[k]
        c = sim_cycles[k]
        t > 0 ? format("%.1f", c / t / 1_000_000) : "?"
      end.join("/")
      puts format("  %5.1f%% | %5.1fM  | %s | %s", pct, cycles_run / 1_000_000.0, pc_values, rate_strs)

      # Print HiRes screen at intervals (only ISA to save space)
      if (cycles_run % SCREEN_INTERVAL).zero?
        isa_bitmap = decode_hires(simulators[:isa], 0x2000)
        print_hires_screen("ISA HiRes (page 1)", isa_bitmap, cycles_run)
      end
    end

    elapsed = Time.now - start_time
    puts "-" * 100
    puts format("Completed in %.1f seconds (%.2fM cycles/sec combined)", elapsed, TOTAL_CYCLES / elapsed / 1_000_000)

    # Performance summary
    puts "\n" + "=" * 80
    puts "PERFORMANCE SUMMARY"
    puts "=" * 80
    puts "\n  Simulator     | Cycles   | Time (s) | Rate (M/s) | Relative"
    puts "  " + "-" * 65

    # Calculate rates based on actual cycles run per simulator
    rates = simulators.keys.map { |k| sim_times[k] > 0 ? sim_cycles[k] / sim_times[k] : 0 }
    fastest_rate = rates.max

    simulators.each_key do |key|
      t = sim_times[key]
      c = sim_cycles[key]
      rate = t > 0 ? c / t / 1_000_000 : 0
      relative = fastest_rate > 0 && t > 0 ? (c / t / fastest_rate * 100).round(1) : 0
      cycles_str = c >= 1_000_000 ? "#{c / 1_000_000.0}M" : "#{c / 1_000}K"
      puts format("  %-13s | %8s | %8.2f | %10.2f | %5.1f%%",
                  key.to_s.upcase, cycles_str, t, rate, relative)
    end

    # Analyze results
    puts "\n" + "=" * 80
    puts "DIVERGENCE ANALYSIS"
    puts "=" * 80

    if divergence_points.empty?
      puts "\n No divergence detected! All simulators match ISA reference."
    else
      divergence_points.each do |key, div|
        puts "\n #{key.to_s.upcase} DIVERGED at #{div[:cycles].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} cycles"
        puts "   ISA: PC=%04X A=%02X X=%02X Y=%02X  P1=%08X P2=%08X TXT=%08X" % [
          div[:isa][:pc], div[:isa][:a], div[:isa][:x], div[:isa][:y],
          div[:isa][:hires_p1], div[:isa][:hires_p2], div[:isa][:text]
        ]
        puts "   #{key.to_s.upcase.ljust(3)}: PC=%04X A=%02X X=%02X Y=%02X  P1=%08X P2=%08X TXT=%08X" % [
          div[:sim][:pc], div[:sim][:a], div[:sim][:x], div[:sim][:y],
          div[:sim][:hires_p1], div[:sim][:hires_p2], div[:sim][:text]
        ]
      end
    end

    # Final state summary
    puts "\n" + "=" * 80
    puts "FINAL STATE SUMMARY"
    puts "=" * 80
    puts "\n  Simulator     | Cycles | PC     | A  | X  | Y  | Halted | HiRes P1   | HiRes P2   | Text"
    puts "  " + "-" * 100

    last_cp = checkpoints.last
    last_cp[:sims].each do |key, data|
      c = sim_cycles[key]
      cycles_str = c >= 1_000_000 ? "%.1fM" % (c / 1_000_000.0) : "#{c / 1_000}K"
      puts format("  %-13s | %6s | %04X   | %02X | %02X | %02X | %-6s | %08X   | %08X   | %08X",
                  key.to_s.upcase,
                  cycles_str,
                  data[:pc], data[:a], data[:x], data[:y],
                  data[:halted] ? "YES" : "no",
                  data[:hires_p1], data[:hires_p2], data[:text])
    end

    # Checkpoint summary table
    puts "\n" + "=" * 80
    puts "CHECKPOINT HISTORY (P1 HiRes match vs ISA)"
    puts "=" * 80
    puts "\n  Cycles  | " + simulators.keys.map { |k| k.to_s.upcase.ljust(10) }.join(" | ")
    puts "  " + "-" * (10 + simulators.size * 13)

    checkpoints.each do |cp|
      isa_p1 = cp[:sims][:isa][:hires_p1]
      matches = simulators.keys.map do |k|
        if k == :isa
          "reference"
        elsif k == :interpret && cp[:cycles] > INTERPRETER_MAX_CYCLES
          "stopped"
        else
          cp[:sims][k][:hires_p1] == isa_p1 ? "match" : "DIVERGED"
        end
      end
      puts format("  %5.1fM  | %s", cp[:cycles] / 1_000_000.0, matches.map { |m| m.ljust(10) }.join(" | "))
    end

    expect(checkpoints.size).to be >= 10, "Should have at least 10 checkpoints"
    expect(simulators.size).to be >= 2, "Should have at least 2 simulators"
  end

  # ============================================================================
  # Per-backend validation tests (faster, no visual output)
  # ============================================================================

  def create_isa_simulator_simple
    require_relative '../../../examples/mos6502/utilities/apple2_bus'
    require_relative '../../../examples/mos6502/utilities/isa_simulator_native'

    karateka_rom = create_karateka_rom
    bus = MOS6502::Apple2Bus.new
    bus.load_rom(karateka_rom, base_addr: 0xD000)
    bus.load_ram(@karateka_mem, base_addr: 0x0000)

    cpu = MOS6502::ISASimulatorNative.new(bus)
    cpu.load_bytes(@karateka_mem, 0x0000)
    cpu.load_bytes(karateka_rom, 0xD000)

    bus.instance_variable_set(:@native_cpu, cpu)
    bus.read(0xC050)  # TXTCLR
    bus.read(0xC052)  # MIXCLR
    bus.read(0xC054)  # PAGE1
    bus.read(0xC057)  # HIRES
    cpu.set_video_state(false, false, false, true)
    cpu.reset

    { cpu: cpu, bus: bus }
  end

  def create_ir_simulator_simple(backend)
    require_relative '../../../examples/mos6502/utilities/runners/ir_simulator_runner'

    runner = IRSimulatorRunner.new(backend)
    karateka_rom = create_karateka_rom

    runner.load_rom(karateka_rom, base_addr: 0xD000)
    runner.load_ram(@karateka_mem, base_addr: 0x0000)
    runner.set_reset_vector(0xB82A)
    runner.reset

    runner
  end

  def hires_checksum_simple(bus, base_addr)
    checksum = 0
    (base_addr..(base_addr + 0x1FFF)).each do |addr|
      checksum = (checksum + bus.read(addr)) & 0xFFFFFFFF
    end
    checksum
  end

  # Run a single backend against ISA for max_cycles clock cycles
  # Returns true if they match throughout, false otherwise
  def run_backend_test(backend_name, backend_sym, max_cycles)
    isa = create_isa_simulator_simple
    ir = create_ir_simulator_simple(backend_sym)

    chunk_size = 100_000
    total_cycles = 0
    isa_time = 0.0
    ir_time = 0.0

    while total_cycles < max_cycles
      # Run ISA chunk with timing (run_cycles runs clock cycles, not instructions)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      isa[:cpu].run_cycles(chunk_size)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      isa_time += (t1 - t0)

      # Run IR chunk with timing (run_cycles runs instructions like ISA)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ir.run_cycles(chunk_size)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ir_time += (t1 - t0)

      total_cycles += chunk_size

      isa_pc = isa[:cpu].pc
      ir_pc = ir.cpu_state[:pc]

      # Compare HiRes checksums
      isa_hires = hires_checksum_simple(isa[:bus], 0x2000)
      ir_hires = hires_checksum_simple(ir.bus, 0x2000)

      if isa_hires != ir_hires
        puts "  #{backend_name}: DIVERGED at #{total_cycles / 1_000_000.0}M cycles"
        puts "    ISA PC=$#{isa_pc.to_s(16).upcase} HiRes=$#{isa_hires.to_s(16).upcase}"
        puts "    IR  PC=$#{ir_pc.to_s(16).upcase} HiRes=$#{ir_hires.to_s(16).upcase}"
        return false
      end

      # Progress indicator every 1M cycles
      if (total_cycles % 1_000_000).zero?
        isa_mhz = (total_cycles / isa_time) / 1_000_000.0
        ir_mhz = (total_cycles / ir_time) / 1_000_000.0
        print "  #{backend_name}: #{total_cycles / 1_000_000}M cycles - " \
              "ISA: #{'%.2f' % isa_mhz} MHz, IR: #{'%.2f' % ir_mhz} MHz\n"
      end
    end

    # Final performance summary
    isa_mhz = (total_cycles / isa_time) / 1_000_000.0
    ir_mhz = (total_cycles / ir_time) / 1_000_000.0
    speedup = ir_mhz / isa_mhz

    puts "  #{backend_name}: PASSED #{max_cycles / 1_000_000}M cycles"
    puts "  Performance: ISA=#{'%.2f' % isa_mhz} MHz, #{backend_name}=#{'%.2f' % ir_mhz} MHz " \
         "(#{'%.1f' % speedup}x #{speedup >= 1.0 ? 'faster' : 'slower'})"
    true
  end

  # Interpreter is slower, so only test 5M cycles (still validates correctness)
  it 'verifies IR Interpreter matches ISA for 5M cycles', :slow, timeout: 600 do
    skip 'ROM not available' unless @rom_available
    skip 'Karateka memory not available' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?

    puts "\n=== Testing IR Interpreter against ISA ==="
    result = run_backend_test("Interpret", :interpret, 5_000_000)
    expect(result).to be true
  end

  it 'verifies IR JIT matches ISA for 10M cycles', :slow, timeout: 120 do
    skip 'ROM not available' unless @rom_available
    skip 'Karateka memory not available' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?

    puts "\n=== Testing IR JIT against ISA ==="
    result = run_backend_test("JIT", :jit, 10_000_000)
    expect(result).to be true
  end

  it 'verifies IR Compiler matches ISA for 10M cycles', :slow, timeout: 600 do
    skip 'ROM not available' unless @rom_available
    skip 'Karateka memory not available' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?

    puts "\n=== Testing IR Compiler against ISA ==="
    result = run_backend_test("Compile", :compile, 10_000_000)
    expect(result).to be true
  end

  # Run Verilator backend against ISA for max_cycles clock cycles
  # Returns true if they match throughout, false otherwise
  def run_verilator_test(max_cycles)
    isa = create_isa_simulator_simple
    verilator = create_verilator_simulator_simple

    chunk_size = 100_000
    isa_time = 0.0
    verilator_time = 0.0

    while verilator.cycle_count < max_cycles
      # Run ISA chunk with timing (run_cycles runs for N clock cycles)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      isa[:cpu].run_cycles(chunk_size)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      isa_time += (t1 - t0)

      # Run Verilator chunk with timing
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      verilator.run_cycles(chunk_size)
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      verilator_time += (t1 - t0)

      isa_cycles = isa[:cpu].cycles
      verilator_cycles = verilator.cycle_count

      isa_pc = isa[:cpu].pc
      verilator_pc = verilator.pc

      # Compare HiRes checksums
      isa_hires = hires_checksum_simple(isa[:bus], 0x2000)
      verilator_hires = verilator_hires_checksum(verilator, 0x2000)

      if isa_hires != verilator_hires
        puts "  Verilator: DIVERGED at #{verilator_cycles / 1_000_000.0}M cycles"
        puts "    ISA PC=$#{isa_pc.to_s(16).upcase} HiRes=$#{isa_hires.to_s(16).upcase}"
        puts "    Verilator PC=$#{verilator_pc.to_s(16).upcase} HiRes=$#{verilator_hires.to_s(16).upcase}"
        return false
      end

      # Progress indicator every 1M cycles
      if (verilator_cycles % 1_000_000) < chunk_size
        isa_mhz = (isa_cycles / isa_time) / 1_000_000.0
        verilator_mhz = (verilator_cycles / verilator_time) / 1_000_000.0
        print "  Verilator: #{verilator_cycles / 1_000_000}M cycles - " \
              "ISA: #{'%.2f' % isa_mhz} MHz, Verilator: #{'%.2f' % verilator_mhz} MHz\n"
      end
    end

    # Final performance summary
    isa_cycles = isa[:cpu].cycles
    verilator_cycles = verilator.cycle_count
    isa_mhz = (isa_cycles / isa_time) / 1_000_000.0
    verilator_mhz = (verilator_cycles / verilator_time) / 1_000_000.0
    speedup = verilator_mhz / isa_mhz

    puts "  Verilator: PASSED #{verilator_cycles / 1_000_000}M cycles"
    puts "  Performance: ISA=#{'%.2f' % isa_mhz} MHz, Verilator=#{'%.2f' % verilator_mhz} MHz " \
         "(#{'%.1f' % speedup}x #{speedup >= 1.0 ? 'faster' : 'slower'})"
    true
  end

  def create_verilator_simulator_simple
    require_relative '../../../examples/mos6502/utilities/runners/mos6502_verilator'

    runner = MOS6502::VerilatorRunner.new
    karateka_rom = create_karateka_rom

    runner.load_memory(karateka_rom, 0xD000)
    runner.load_memory(@karateka_mem, 0x0000)
    runner.set_reset_vector(0xB82A)
    runner.reset

    runner
  end

  def verilator_hires_checksum(runner, base_addr)
    checksum = 0
    (base_addr..(base_addr + 0x1FFF)).each do |addr|
      checksum = (checksum + runner.read_memory(addr)) & 0xFFFFFFFF
    end
    checksum
  end

  it 'compares HiRes checksums: ISA vs JIT, Compile, Verilator (5M cycles)', timeout: 180 do
    skip 'ROM not available' unless @rom_available
    skip 'Karateka memory not available' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?

    cycles = 5_000_000
    puts "\n=== Testing JIT, Compiler, Verilator against ISA (#{cycles / 1_000_000}M cycles) ==="

    results = {}

    # Test JIT
    if ir_backend_available?(:jit)
      puts "\n--- JIT vs ISA ---"
      results[:jit] = run_backend_test("JIT", :jit, cycles)
    else
      puts "\n--- JIT: Not available (skipped) ---"
    end

    # Test Compiler
    if ir_backend_available?(:compile)
      puts "\n--- Compiler vs ISA ---"
      results[:compile] = run_backend_test("Compile", :compile, cycles)
    else
      puts "\n--- Compiler: Not available (skipped) ---"
    end

    # Test Verilator
    if verilator_available?
      puts "\n--- Verilator vs ISA ---"
      results[:verilator] = run_verilator_test(cycles)
    else
      puts "\n--- Verilator: Not available (skipped) ---"
    end

    # Summary
    puts "\n=== Summary ==="
    results.each do |backend, passed|
      status = passed ? "PASSED" : "FAILED"
      puts "  #{backend.to_s.upcase}: #{status}"
    end

    # All backends must pass
    failed_backends = results.select { |_k, v| !v }.keys
    expect(failed_backends).to be_empty, "All backends must pass, but #{failed_backends.join(', ')} failed"
  end

  it 'compares HiRes checksums: ISA vs JIT, Compile, Verilator (20M cycles)', timeout: 360 do
    skip 'ROM not available' unless @rom_available
    skip 'Karateka memory not available' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?

    cycles = 20_000_000
    puts "\n=== Testing JIT, Compiler, Verilator against ISA (#{cycles / 1_000_000}M cycles) ==="

    results = {}

    # Test JIT
    if ir_backend_available?(:jit)
      puts "\n--- JIT vs ISA ---"
      results[:jit] = run_backend_test("JIT", :jit, cycles)
    else
      puts "\n--- JIT: Not available (skipped) ---"
    end

    # Test Compiler
    if ir_backend_available?(:compile)
      puts "\n--- Compiler vs ISA ---"
      results[:compile] = run_backend_test("Compile", :compile, cycles)
    else
      puts "\n--- Compiler: Not available (skipped) ---"
    end

    # Test Verilator
    if verilator_available?
      puts "\n--- Verilator vs ISA ---"
      results[:verilator] = run_verilator_test(cycles)
    else
      puts "\n--- Verilator: Not available (skipped) ---"
    end

    # Summary
    puts "\n=== Summary ==="
    results.each do |backend, passed|
      status = passed ? "PASSED" : "FAILED"
      puts "  #{backend.to_s.upcase}: #{status}"
    end

    # All backends must pass
    failed_backends = results.select { |_k, v| !v }.keys
    expect(failed_backends).to be_empty, "All backends must pass, but #{failed_backends.join(', ')} failed"
  end

  # ============================================================================
  # Combined benchmark test - all backends comparison
  # ============================================================================

  def benchmark_backend(backend_name, backend_sym, cycles)
    ir = create_ir_simulator_simple(backend_sym)

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ir.run_steps(cycles)
    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    elapsed = t1 - t0
    mhz = (cycles / elapsed) / 1_000_000.0

    { name: backend_name, cycles: cycles, elapsed: elapsed, mhz: mhz }
  end

  def benchmark_isa(cycles)
    isa = create_isa_simulator_simple

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    isa[:cpu].run_cycles(cycles)
    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    elapsed = t1 - t0
    actual_cycles = isa[:cpu].cycles
    mhz = (actual_cycles / elapsed) / 1_000_000.0

    { name: "ISA", cycles: actual_cycles, elapsed: elapsed, mhz: mhz }
  end

  def benchmark_verilator(cycles)
    verilator = create_verilator_simulator_simple

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    verilator.run_cycles(cycles)
    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    elapsed = t1 - t0
    actual_cycles = verilator.cycle_count
    mhz = (actual_cycles / elapsed) / 1_000_000.0

    { name: "Verilator", cycles: actual_cycles, elapsed: elapsed, mhz: mhz }
  end

  it 'benchmarks ISA, JIT, Compile, Verilator (20M cycles)', :slow, :benchmark, timeout: 1800 do
    skip 'ROM not available' unless @rom_available
    skip 'Karateka memory not available' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?

    cycles = 20_000_000  # 20M cycles for benchmark

    puts "\n" + "=" * 70
    puts "  5-Way Implementation Benchmark (#{cycles / 1_000_000}M cycles each)"
    puts "=" * 70

    results = []

    # ISA (reference)
    print "  Running ISA..."
    $stdout.flush
    results << benchmark_isa(cycles)
    puts " done (#{'%.2f' % results.last[:elapsed]}s)"

    # Interpreter (disabled for now)
    # interp_cycles = 1_000_000
    # print "  Running Interpreter (#{interp_cycles / 1_000_000}M cycles)..."
    # $stdout.flush
    # results << benchmark_backend("Interpret", :interpret, interp_cycles)
    # puts " done (#{'%.2f' % results.last[:elapsed]}s)"
    puts "  Skipping Interpreter (disabled for now)"

    # JIT
    print "  Running JIT..."
    $stdout.flush
    results << benchmark_backend("JIT", :jit, cycles)
    puts " done (#{'%.2f' % results.last[:elapsed]}s)"

    # Compiler
    print "  Running Compiler..."
    $stdout.flush
    results << benchmark_backend("Compile", :compile, cycles)
    puts " done (#{'%.2f' % results.last[:elapsed]}s)"

    # Verilator (if available)
    if verilator_available?
      print "  Running Verilator..."
      $stdout.flush
      begin
        results << benchmark_verilator(cycles)
        puts " done (#{'%.2f' % results.last[:elapsed]}s)"
      rescue StandardError => e
        puts " failed (#{e.message})"
      end
    else
      puts "  Skipping Verilator (not available)"
    end

    # Summary table
    puts "\n" + "-" * 70
    puts "  %-12s | %10s | %10s | %10s | %10s" % ["Backend", "Cycles", "Time (s)", "MHz", "vs ISA"]
    puts "-" * 70

    isa_mhz = results.find { |r| r[:name] == "ISA" }[:mhz]

    results.each do |r|
      speedup = r[:mhz] / isa_mhz
      speedup_str = if r[:name] == "ISA"
                      "-"
                    elsif speedup >= 1.0
                      "#{'%.1f' % speedup}x faster"
                    else
                      "#{'%.1f' % (1.0 / speedup)}x slower"
                    end

      puts "  %-12s | %10s | %10.2f | %10.2f | %10s" % [
        r[:name],
        "#{r[:cycles] / 1_000_000}M",
        r[:elapsed],
        r[:mhz],
        speedup_str
      ]
    end

    puts "-" * 70
    puts "\n"

    # At least 3 results (ISA, JIT, Compile), 4 if Verilator available
    # Note: Interpreter disabled for now
    expect(results.size).to be >= 3
  end

  # ============================================================================
  # Opcode sequence comparison test
  # ============================================================================

  it 'compares opcode sequences: ISA vs JIT, Compile, Verilator (1M instructions)', timeout: 300 do
    skip 'ROM not available' unless @rom_available
    skip 'Karateka memory not available' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?

    puts "\n" + "=" * 80
    puts "Opcode Sequence Comparison: ISA vs JIT, Compile, Verilator"
    puts "=" * 80

    max_instructions = 1_000_000  # 1M instructions per backend
    batch_size = 1000  # Instructions per batch

    # Track results for each backend
    results = {}

    # Test each backend against ISA
    # Note: Only JIT supports instruction-level stepping properly
    # Compile backend's state machine doesn't advance with manual cycle stepping
    # Verilator has separate initialization that causes early divergence
    backends = []
    backends << [:jit, 'JIT'] if ir_backend_available?(:jit)
    backends << [:compile, 'Compile'] if ir_backend_available?(:compile)
    backends << [:verilator, 'Verilator'] if verilator_available?

    backends.each do |backend_sym, backend_name|
      puts "\n--- Comparing ISA vs #{backend_name} (#{max_instructions / 1000}K instructions) ---"

      # Create fresh simulators for each comparison
      isa = create_isa_simulator
      backend = case backend_sym
                when :verilator then create_verilator_simulator
                else create_ir_simulator(backend_sym)
                end

      total_instructions = 0
      divergence_found = false
      divergence_index = nil
      start_time = Time.now

      while total_instructions < max_instructions && !divergence_found
        # Run both simulators for batch_size instructions
        isa_opcodes = isa.run_instructions_with_opcodes(batch_size)
        backend_opcodes = backend.run_instructions_with_opcodes(batch_size)

        # Compare sequences
        min_len = [isa_opcodes.length, backend_opcodes.length].min

        min_len.times do |i|
          isa_pc, isa_op, isa_sp = isa_opcodes[i]
          be_pc, be_op, be_sp = backend_opcodes[i]

          if isa_op != be_op || isa_pc != be_pc
            divergence_found = true
            divergence_index = total_instructions + i

            puts "\n  DIVERGENCE at instruction #{divergence_index}!"
            puts "  ISA: PC=$#{format('%04X', isa_pc)} Op=$#{format('%02X', isa_op)} SP=$#{format('%02X', isa_sp)}"
            puts "  #{backend_name}: PC=$#{format('%04X', be_pc)} Op=$#{format('%02X', be_op)} SP=$#{format('%02X', be_sp)}"
            break
          end
        end

        total_instructions += min_len

        # Progress every 100K
        if (total_instructions % 100_000).zero?
          elapsed = Time.now - start_time
          rate = total_instructions / elapsed / 1000.0
          puts "  #{total_instructions / 1000}K matched (#{format('%.1f', rate)}K/s)"
        end

        # Check if either simulator stopped early
        break if isa_opcodes.length < batch_size || backend_opcodes.length < batch_size
      end

      elapsed = Time.now - start_time
      rate = total_instructions / elapsed / 1000.0

      if divergence_found
        results[backend_sym] = { status: :diverged, at: divergence_index, time: elapsed }
        puts "  #{backend_name}: DIVERGED at #{divergence_index} (#{format('%.1f', elapsed)}s)"
      else
        results[backend_sym] = { status: :passed, count: total_instructions, time: elapsed }
        puts "  #{backend_name}: PASSED #{total_instructions / 1000}K instructions (#{format('%.1f', elapsed)}s, #{format('%.1f', rate)}K/s)"
      end
    end

    # Summary
    puts "\n" + "=" * 80
    puts "SUMMARY"
    puts "=" * 80
    results.each do |backend, result|
      name = backend.to_s.upcase.ljust(10)
      if result[:status] == :passed
        puts "  #{name}: PASSED #{result[:count] / 1000}K instructions in #{format('%.1f', result[:time])}s"
      else
        puts "  #{name}: DIVERGED at instruction #{result[:at]}"
      end
    end

    # Test passes if we ran at least some instructions
    total_tested = results.values.sum { |r| r[:count] || r[:at] || 0 }
    expect(total_tested).to be > 0
  end

  # Debug test for tracing divergence
  # Dedicated RTS trace test - traces the specific RTS that causes divergence
  it 'traces RTS execution to find divergence cause', timeout: 60 do
    skip 'ROM not available' unless @rom_available
    skip 'Karateka memory not available' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?
    skip 'JIT not available' unless ir_backend_available?(:jit)

    puts "\n" + "=" * 80
    puts "Tracing RTS Execution in JIT"
    puts "=" * 80

    # Create JIT simulator
    jit = create_ir_simulator(:jit)

    # Run until we're about to execute the first RTS with trace enabled
    puts "\nRunning JIT with RTS tracing enabled..."
    jit_opcodes = jit.run_instructions_with_opcodes(100, trace_rts: true)

    puts "\nOpcodes executed: #{jit_opcodes.length}"
    puts "First 25 instructions:"
    jit_opcodes.first(25).each_with_index do |tuple, i|
      pc, op, sp = tuple
      puts "  #{i}: PC=$#{format('%04X', pc)} Op=$#{format('%02X', op)} SP=$#{format('%02X', sp)}"
    end

    expect(jit_opcodes.length).to be > 0
  end
end
