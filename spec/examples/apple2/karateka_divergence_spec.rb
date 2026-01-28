# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/hdl/apple2'

RSpec.describe 'Karateka ISA vs IR Compiler Divergence' do
  # Test to verify that IR compiler executes the same instructions as ISA
  # The IR may have extra PC values (cycle-level granularity) but should
  # contain all ISA PC values in the same order as a subsequence.

  ROM_PATH = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  KARATEKA_MEM_PATH = File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

  # Test parameters
  TOTAL_CYCLES = 10_000_000
  PC_SAMPLE_INTERVAL = 10_000  # Sample PC every N cycles (batch size)

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

  # Check if isa_pcs is a subsequence of ir_pcs (same order, ir may have extras)
  def is_subsequence?(isa_pcs, ir_pcs)
    return true if isa_pcs.empty?

    isa_idx = 0
    ir_pcs.each do |ir_pc|
      if ir_pc == isa_pcs[isa_idx]
        isa_idx += 1
        return true if isa_idx >= isa_pcs.length
      end
    end

    false
  end

  # Find the longest matching prefix of isa_pcs that is a subsequence of ir_pcs
  def longest_matching_prefix(isa_pcs, ir_pcs)
    return 0 if isa_pcs.empty? || ir_pcs.empty?

    isa_idx = 0
    ir_pcs.each do |ir_pc|
      if ir_pc == isa_pcs[isa_idx]
        isa_idx += 1
        break if isa_idx >= isa_pcs.length
      end
    end

    isa_idx
  end

  # Find where the sequences first diverge
  def find_divergence_point(isa_pcs, ir_pcs)
    return nil if isa_pcs.empty? || ir_pcs.empty?

    isa_idx = 0
    ir_idx = 0

    while isa_idx < isa_pcs.length && ir_idx < ir_pcs.length
      if ir_pcs[ir_idx] == isa_pcs[isa_idx]
        isa_idx += 1
        ir_idx += 1
      else
        ir_idx += 1
        # If we've scanned too far without finding the next ISA PC, we've diverged
        if ir_idx - isa_idx > 10000
          return {
            isa_index: isa_idx,
            isa_pc: isa_pcs[isa_idx],
            ir_index: ir_idx - 10000,
            last_matched_isa_index: isa_idx - 1,
            last_matched_pc: isa_idx > 0 ? isa_pcs[isa_idx - 1] : nil
          }
        end
      end
    end

    # Check if we matched all ISA PCs
    if isa_idx < isa_pcs.length
      {
        isa_index: isa_idx,
        isa_pc: isa_pcs[isa_idx],
        ir_index: ir_idx,
        last_matched_isa_index: isa_idx - 1,
        last_matched_pc: isa_idx > 0 ? isa_pcs[isa_idx - 1] : nil
      }
    else
      nil  # All matched
    end
  end

  it 'verifies IR PC sequence contains ISA PC sequence as subsequence', :slow do
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
    puts "Karateka ISA vs IR Compiler PC Sequence Analysis"
    puts "Total cycles: #{TOTAL_CYCLES.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "PC sample interval: every #{PC_SAMPLE_INTERVAL} cycles"
    puts "=" * 70

    # Create simulators
    puts "\nInitializing simulators..."
    isa_cpu, _isa_bus = create_isa_simulator
    ir_sim = create_ir_compiler

    puts "  ISA: Native Rust ISA simulator"
    puts "  IR:  Rust IR Compiler (sub_cycles=14)"

    # Collect PC sequences (deduplicated - consecutive duplicates removed)
    isa_pcs = []
    ir_pcs = []
    last_isa_pc = nil
    last_ir_pc = nil

    cycles_run = 0
    start_time = Time.now
    last_report = 0

    puts "\nCollecting PC sequences..."
    puts "-" * 70

    while cycles_run < TOTAL_CYCLES
      # Run batch of cycles
      batch_size = [PC_SAMPLE_INTERVAL, TOTAL_CYCLES - cycles_run].min

      # Run ISA batch and sample PC
      batch_size.times do
        break if isa_cpu.halted?
        isa_cpu.step
      end
      pc = isa_cpu.pc
      if pc != last_isa_pc
        isa_pcs << pc
        last_isa_pc = pc
      end

      # Run IR batch and sample PC
      ir_sim.run_cpu_cycles(batch_size, 0, false)
      pc = ir_sim.peek('cpu__pc_reg')
      if pc != last_ir_pc
        ir_pcs << pc
        last_ir_pc = pc
      end

      cycles_run += batch_size

      # Progress output every 1M cycles
      if cycles_run - last_report >= 1_000_000
        elapsed = Time.now - start_time
        rate = cycles_run / elapsed / 1_000_000
        pct = (cycles_run.to_f / TOTAL_CYCLES * 100).round(1)
        puts format("  %5.1f%% | %7.1fM cycles | ISA PCs: %6d | IR PCs: %6d | %.2fM/s",
                    pct, cycles_run / 1_000_000.0, isa_pcs.size, ir_pcs.size, rate)
        last_report = cycles_run
      end
    end

    elapsed = Time.now - start_time
    puts "-" * 70
    puts format("Completed in %.1f seconds (%.2fM cycles/sec)", elapsed, TOTAL_CYCLES / elapsed / 1_000_000)

    # Analyze results
    puts "\n" + "=" * 70
    puts "PC SEQUENCE ANALYSIS"
    puts "=" * 70

    puts "\nSequence sizes:"
    puts "  ISA unique PCs: #{isa_pcs.size}"
    puts "  IR unique PCs:  #{ir_pcs.size}"

    # Check subsequence relationship
    matching_prefix = longest_matching_prefix(isa_pcs, ir_pcs)
    match_pct = (matching_prefix.to_f / isa_pcs.size * 100).round(2)

    puts "\nSubsequence analysis:"
    puts "  Longest matching prefix: #{matching_prefix} / #{isa_pcs.size} ISA PCs (#{match_pct}%)"

    if matching_prefix < isa_pcs.size
      divergence = find_divergence_point(isa_pcs, ir_pcs)
      if divergence
        puts "\n  Divergence detected:"
        puts "    ISA PC index: #{divergence[:isa_index]}"
        puts "    Missing ISA PC: $#{divergence[:isa_pc].to_s(16).upcase.rjust(4, '0')}"
        puts "    Last matched PC: $#{divergence[:last_matched_pc]&.to_s(16)&.upcase&.rjust(4, '0') || 'none'}"

        # Show context around divergence
        puts "\n  ISA PC context around divergence:"
        start_idx = [0, divergence[:isa_index] - 5].max
        end_idx = [isa_pcs.size - 1, divergence[:isa_index] + 5].min
        (start_idx..end_idx).each do |i|
          marker = i == divergence[:isa_index] ? " <-- MISSING" : ""
          puts "    [#{i}] $#{isa_pcs[i].to_s(16).upcase.rjust(4, '0')}#{marker}"
        end
      end
    else
      puts "\n  All ISA PCs found in IR sequence in correct order!"
    end

    # Show first few PCs from each sequence
    puts "\nFirst 20 unique PCs:"
    puts "  ISA: #{isa_pcs.first(20).map { |pc| '$' + pc.to_s(16).upcase.rjust(4, '0') }.join(' ')}"
    puts "  IR:  #{ir_pcs.first(20).map { |pc| '$' + pc.to_s(16).upcase.rjust(4, '0') }.join(' ')}"

    # Assertions
    expect(isa_pcs.size).to be > 0, "Should have collected ISA PCs"
    expect(ir_pcs.size).to be > 0, "Should have collected IR PCs"

    # The key assertion: ISA PC sequence should be a subsequence of IR PC sequence
    # This means every instruction the ISA executes, the IR should also execute in the same order
    expect(match_pct).to be >= 95.0,
      "IR should contain at least 95% of ISA PCs as a subsequence, got #{match_pct}%"
  end
end
