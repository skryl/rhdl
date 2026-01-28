# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/hdl/apple2'

RSpec.describe 'Karateka ISA vs IR Compiler 40M Divergence' do
  ROM_PATH = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  KARATEKA_MEM_PATH = File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

  TOTAL_CYCLES = 40_000_000
  CHECKPOINT_INTERVAL = 2_000_000

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
    rom[0x2FFC] = 0x2A
    rom[0x2FFD] = 0xB8
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
    (0x2000..0x3FFF).each { |addr| checksum = (checksum + bus.read(addr)) & 0xFFFFFFFF }
    checksum
  end

  def hires_checksum_ir(sim)
    checksum = 0
    sim.read_ram(0x2000, 0x2000).to_a.each { |b| checksum = (checksum + b) & 0xFFFFFFFF }
    checksum
  end

  it 'runs 40M cycles', timeout: 1200 do
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
    puts "Karateka 40M Cycle Test"
    puts "=" * 70

    isa_cpu, isa_bus = create_isa_simulator
    ir_sim = create_ir_compiler

    checkpoints = []
    cycles_run = 0
    start_time = Time.now

    while cycles_run < TOTAL_CYCLES
      batch_size = [CHECKPOINT_INTERVAL, TOTAL_CYCLES - cycles_run].min

      batch_size.times do
        break if isa_cpu.halted?
        isa_cpu.step
      end

      ir_sim.run_cpu_cycles(batch_size, 0, false)
      cycles_run += batch_size

      isa_pc = isa_cpu.pc
      ir_pc = ir_sim.peek('cpu__pc_reg')
      isa_hires = hires_checksum_isa(isa_bus)
      ir_hires = hires_checksum_ir(ir_sim)

      checkpoint = {
        cycles: cycles_run,
        isa_pc: isa_pc,
        ir_pc: ir_pc,
        hires_match: isa_hires == ir_hires
      }
      checkpoints << checkpoint

      elapsed = Time.now - start_time
      rate = cycles_run / elapsed / 1_000_000
      pct = (cycles_run.to_f / TOTAL_CYCLES * 100).round(1)

      puts format("  %5.1f%% | %7.1fM | ISA=$%04X IR=$%04X | HiRes: %s | %.2fM/s",
                  pct, cycles_run / 1_000_000.0, isa_pc, ir_pc,
                  checkpoint[:hires_match] ? "match" : "DIFF", rate)
    end

    # Check results
    hires_match_count = checkpoints.count { |cp| cp[:hires_match] }
    hires_match_pct = (hires_match_count * 100.0 / checkpoints.size).round(1)

    puts "\n" + "=" * 70
    puts "Results: HiRes match #{hires_match_pct}% (#{hires_match_count}/#{checkpoints.size})"
    puts "=" * 70

    # HiRes should match for at least 90% of checkpoints
    expect(hires_match_pct).to be >= 90.0,
      "HiRes should match for at least 90% of checkpoints, got #{hires_match_pct}%"
  end
end
