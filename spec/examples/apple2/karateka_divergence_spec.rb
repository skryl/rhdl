# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/hdl/apple2'

RSpec.describe 'Karateka ISA vs IR Compiler Divergence' do
  # Debug test to identify where ISA runner and IR compiler diverge
  # during Karateka game intro (around 5M cycles)

  ROM_PATH = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  KARATEKA_MEM_PATH = File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

  # Test parameters
  TOTAL_CYCLES = 20_000_000
  CHECKPOINT_INTERVAL = 500_000  # Check every 500K cycles

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
    cpu.reset

    [cpu, bus]
  end

  def create_ir_compiler
    require 'rhdl/codegen'

    ir = RHDL::Apple2::Apple2.to_flat_ir
    ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)

    sim = RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json, sub_cycles: 14)

    karateka_rom = create_karateka_rom
    sim.load_rom(karateka_rom)
    sim.load_ram(@karateka_mem.first(48 * 1024), 0)

    sim.poke('reset', 1)
    sim.tick
    sim.poke('reset', 0)
    3.times { sim.run_cpu_cycles(1, 0, false) }

    sim
  end

  def hires_checksum_isa(bus)
    checksum = 0
    (0x2000..0x3FFF).each do |addr|
      checksum = (checksum + bus.read(addr)) & 0xFFFFFFFF
    end
    checksum
  end

  def hires_checksum_ir(sim)
    checksum = 0
    data = sim.read_ram(0x2000, 0x2000).to_a
    data.each { |b| checksum = (checksum + b) & 0xFFFFFFFF }
    checksum
  end

  def text_checksum_isa(bus)
    checksum = 0
    (0x0400..0x07FF).each do |addr|
      checksum = (checksum + bus.read(addr)) & 0xFFFFFFFF
    end
    checksum
  end

  def text_checksum_ir(sim)
    checksum = 0
    data = sim.read_ram(0x0400, 0x400).to_a
    data.each { |b| checksum = (checksum + b) & 0xFFFFFFFF }
    checksum
  end

  it 'compares ISA vs IR compiler over 20M cycles', timeout: 1200 do
    skip 'AppleIIgo ROM not found' unless @rom_available
    skip 'Karateka memory dump not found' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?

    begin
      require 'rhdl/codegen'
      skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
    rescue LoadError
      skip 'IR Codegen not available'
    end

    puts "\n" + "=" * 70
    puts "Karateka ISA vs IR Compiler Divergence Analysis"
    puts "Total cycles: #{TOTAL_CYCLES.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "=" * 70

    # Create simulators
    puts "\nInitializing simulators..."
    isa_cpu, isa_bus = create_isa_simulator
    ir_sim = create_ir_compiler

    puts "  ISA: Native Rust ISA simulator"
    puts "  IR:  Rust IR Compiler (sub_cycles=14)"

    # Track state at checkpoints
    checkpoints = []
    divergence_point = nil

    cycles_run = 0
    start_time = Time.now

    puts "\nRunning comparison..."
    puts "-" * 70

    while cycles_run < TOTAL_CYCLES
      # Run batch of cycles
      batch_size = [CHECKPOINT_INTERVAL, TOTAL_CYCLES - cycles_run].min

      # Run ISA
      batch_size.times do
        break if isa_cpu.halted?
        isa_cpu.step
      end

      # Run IR
      ir_sim.run_cpu_cycles(batch_size, 0, false)

      cycles_run += batch_size

      # Checkpoint
      isa_pc = isa_cpu.pc
      ir_pc = ir_sim.peek('cpu__pc_reg')

      isa_hires = hires_checksum_isa(isa_bus)
      ir_hires = hires_checksum_ir(ir_sim)
      isa_text = text_checksum_isa(isa_bus)
      ir_text = text_checksum_ir(ir_sim)

      isa_a = isa_cpu.a
      isa_x = isa_cpu.x
      isa_y = isa_cpu.y

      ir_a = ir_sim.peek('cpu__a_reg')
      ir_x = ir_sim.peek('cpu__x_reg')
      ir_y = ir_sim.peek('cpu__y_reg')

      checkpoint = {
        cycles: cycles_run,
        isa_pc: isa_pc,
        ir_pc: ir_pc,
        pc_match: isa_pc == ir_pc,
        isa_regs: { a: isa_a, x: isa_x, y: isa_y },
        ir_regs: { a: ir_a, x: ir_x, y: ir_y },
        regs_match: isa_a == ir_a && isa_x == ir_x && isa_y == ir_y,
        isa_hires: isa_hires,
        ir_hires: ir_hires,
        hires_match: isa_hires == ir_hires,
        isa_text: isa_text,
        ir_text: ir_text,
        text_match: isa_text == ir_text
      }
      checkpoints << checkpoint

      # Check for divergence
      if divergence_point.nil? && (!checkpoint[:hires_match] || !checkpoint[:text_match])
        divergence_point = checkpoint
      end

      # Progress output
      elapsed = Time.now - start_time
      rate = cycles_run / elapsed / 1_000_000
      pct = (cycles_run.to_f / TOTAL_CYCLES * 100).round(1)

      puts format("  %5.1f%% | %7.1fM cycles | PC: ISA=%04X IR=%04X %s | HiRes: %s | Text: %s | %.2fM/s",
                  pct,
                  cycles_run / 1_000_000.0,
                  isa_pc, ir_pc,
                  isa_pc == ir_pc ? "=" : "≠",
                  checkpoint[:hires_match] ? "match" : "DIFF",
                  checkpoint[:text_match] ? "match" : "DIFF",
                  rate)
    end

    elapsed = Time.now - start_time
    puts "-" * 70
    puts format("Completed in %.1f seconds (%.2fM cycles/sec)", elapsed, TOTAL_CYCLES / elapsed / 1_000_000)

    # Analyze results
    puts "\n" + "=" * 70
    puts "ANALYSIS"
    puts "=" * 70

    if divergence_point
      puts "\n🔴 DIVERGENCE DETECTED at #{divergence_point[:cycles].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} cycles"
      puts "   ISA PC: 0x#{divergence_point[:isa_pc].to_s(16).upcase}"
      puts "   IR  PC: 0x#{divergence_point[:ir_pc].to_s(16).upcase}"
      puts "   ISA Regs: A=#{divergence_point[:isa_regs][:a].to_s(16)} X=#{divergence_point[:isa_regs][:x].to_s(16)} Y=#{divergence_point[:isa_regs][:y].to_s(16)}"
      puts "   IR  Regs: A=#{divergence_point[:ir_regs][:a].to_s(16)} X=#{divergence_point[:ir_regs][:x].to_s(16)} Y=#{divergence_point[:ir_regs][:y].to_s(16)}"
      puts "   HiRes checksum: ISA=#{divergence_point[:isa_hires].to_s(16)} IR=#{divergence_point[:ir_hires].to_s(16)}"
      puts "   Text checksum:  ISA=#{divergence_point[:isa_text].to_s(16)} IR=#{divergence_point[:ir_text].to_s(16)}"
    else
      puts "\n🟢 No screen divergence detected over #{TOTAL_CYCLES.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} cycles"
    end

    # Summary table
    puts "\nCheckpoint Summary:"
    puts "  Cycles     | PC Match | Regs Match | HiRes Match | Text Match"
    puts "  " + "-" * 60
    checkpoints.each do |cp|
      puts format("  %9s | %-8s | %-10s | %-11s | %-10s",
                  "#{cp[:cycles] / 1_000_000.0}M",
                  cp[:pc_match] ? "yes" : "NO",
                  cp[:regs_match] ? "yes" : "NO",
                  cp[:hires_match] ? "yes" : "NO",
                  cp[:text_match] ? "yes" : "NO")
    end

    expect(checkpoints.size).to be >= 20, "Should have at least 20 checkpoints"
  end
end
