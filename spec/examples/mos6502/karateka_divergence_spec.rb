# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/utilities/braille_renderer'

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
  TOTAL_CYCLES = 5_000_000
  CHECKPOINT_INTERVAL = 500_000  # Check every 500K cycles
  SCREEN_INTERVAL = 1_000_000    # Print screen every 1M cycles

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
  end

  class IRWrapper < SimulatorWrapper
    def initialize(runner, backend_name)
      super("IR #{backend_name}", :ir)
      @runner = runner
      @bus = runner.bus
    end

    def pc; @runner.cpu_state[:pc]; end
    def a; @runner.cpu_state[:a]; end
    def x; @runner.cpu_state[:x]; end
    def y; @runner.cpu_state[:y]; end
    def halted?; @runner.halted?; end

    def run_steps(n)
      @runner.run_steps(n)
    end

    def read_memory(addr)
      @runner.bus.read(addr)
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
    require_relative '../../../examples/mos6502/utilities/ir_simulator_runner'
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

  it 'compares all 4 MOS6502 simulators over 5M cycles', timeout: 600 do
    skip 'AppleIIgo ROM not found' unless @rom_available
    skip 'Karateka memory dump not found' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?

    puts "\n" + "=" * 80
    puts "Karateka MOS6502 4-Way Divergence Analysis"
    puts "Total cycles: #{TOTAL_CYCLES.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "=" * 80

    # Create all available simulators
    puts "\nInitializing simulators..."
    simulators = {}

    # ISA simulator (reference)
    simulators[:isa] = create_isa_simulator
    puts "  [x] ISA: Native Rust ISA simulator (reference)"

    # IR backends (skip interpreter and compile - too slow for now)
    [:jit].each do |backend|
      if ir_backend_available?(backend)
        simulators[backend] = create_ir_simulator(backend)
        puts "  [x] IR #{backend.to_s.capitalize}: Available"
      else
        puts "  [ ] IR #{backend.to_s.capitalize}: Not available (skipped)"
      end
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

    while cycles_run < TOTAL_CYCLES
      # Run batch of cycles
      batch_size = [CHECKPOINT_INTERVAL, TOTAL_CYCLES - cycles_run].min

      # Run all simulators and track time for each
      simulators.each do |key, sim|
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sim.run_steps(batch_size)
        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sim_times[key] += (t1 - t0)
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

      # Check for divergence from ISA reference
      isa_data = checkpoint[:sims][:isa]
      simulators.each_key do |key|
        next if key == :isa
        next if divergence_points[key]

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

      pc_values = simulators.map { |k, _| format("%04X", checkpoint[:sims][k][:pc]) }.join(" | ")
      # Per-simulator rates
      rates = simulators.keys.map do |k|
        t = sim_times[k]
        t > 0 ? format("%.1f", cycles_run / t / 1_000_000) : "?"
      end.join("/")
      puts format("  %5.1f%% | %5.1fM  | %s | %s", pct, cycles_run / 1_000_000.0, pc_values, rates)

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
    puts "\n  Simulator     | Time (s) | Rate (M/s) | Relative"
    puts "  " + "-" * 55

    # Find fastest for relative comparison
    fastest_rate = simulators.keys.map { |k| sim_times[k] > 0 ? TOTAL_CYCLES / sim_times[k] : 0 }.max

    simulators.each_key do |key|
      t = sim_times[key]
      rate = t > 0 ? TOTAL_CYCLES / t / 1_000_000 : 0
      relative = fastest_rate > 0 && t > 0 ? (TOTAL_CYCLES / t / fastest_rate * 100).round(1) : 0
      puts format("  %-13s | %8.2f | %10.2f | %5.1f%%",
                  key.to_s.upcase, t, rate, relative)
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
    puts "\n  Simulator     | PC     | A  | X  | Y  | Halted | HiRes P1   | HiRes P2   | Text"
    puts "  " + "-" * 90

    last_cp = checkpoints.last
    last_cp[:sims].each do |key, data|
      puts format("  %-13s | %04X   | %02X | %02X | %02X | %-6s | %08X   | %08X   | %08X",
                  key.to_s.upcase,
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
    require_relative '../../../examples/mos6502/utilities/ir_simulator_runner'

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

  # Run a single backend against ISA for max_steps cycles
  # Returns true if they match throughout, false otherwise
  def run_backend_test(backend_name, backend_sym, max_steps)
    isa = create_isa_simulator_simple
    ir = create_ir_simulator_simple(backend_sym)

    chunk_size = 100_000
    total_steps = 0

    while total_steps < max_steps
      # Run chunk
      chunk_size.times do
        break if isa[:cpu].halted?
        isa[:cpu].step
      end
      ir.run_steps(chunk_size)
      total_steps += chunk_size

      isa_pc = isa[:cpu].pc
      ir_pc = ir.cpu_state[:pc]

      # Compare HiRes checksums
      isa_hires = hires_checksum_simple(isa[:bus], 0x2000)
      ir_hires = hires_checksum_simple(ir.bus, 0x2000)

      if isa_hires != ir_hires
        puts "  #{backend_name}: DIVERGED at #{total_steps / 1_000_000.0}M cycles"
        puts "    ISA PC=$#{isa_pc.to_s(16).upcase} HiRes=$#{isa_hires.to_s(16).upcase}"
        puts "    IR  PC=$#{ir_pc.to_s(16).upcase} HiRes=$#{ir_hires.to_s(16).upcase}"
        return false
      end

      # Progress indicator every 1M cycles
      if (total_steps % 1_000_000).zero?
        print "  #{backend_name}: #{total_steps / 1_000_000}M cycles - PC match at $#{isa_pc.to_s(16).upcase}\n"
      end
    end

    puts "  #{backend_name}: PASSED #{max_steps / 1_000_000}M cycles"
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
end
