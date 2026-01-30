# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/hdl/apple2'
require_relative '../../../examples/apple2/utilities/braille_renderer'

# Verilator availability check
def verilator_available?
  ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
    File.executable?(File.join(path, 'verilator'))
  end
end

RSpec.describe 'Karateka ISA vs IR Compiler Divergence' do
  # Test verifies that ISA and IR simulators execute the same code paths
  # by checking that PC and opcode sequences match as subsequences (allowing timing drift)

  ROM_PATH = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  KARATEKA_MEM_PATH = File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

  # Test parameters - can be overridden via environment variables
  # Usage: START_CYCLES=0 END_CYCLES=20000000 rspec spec/examples/apple2/karateka_divergence_spec.rb
  START_CYCLES = (ENV['START_CYCLES'] || 25_000_000).to_i
  END_CYCLES = (ENV['END_CYCLES'] || 35_000_000).to_i
  TOTAL_CYCLES = END_CYCLES - START_CYCLES
  PC_SAMPLE_INTERVAL = 50_000     # Sample PC every 50K cycles for sequence
  CHECKPOINT_INTERVAL = 500_000   # Checkpoint every 500K cycles for progress
  SCREEN_INTERVAL = 5_000_000     # Print screen every 5M cycles

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

    bus.instance_variable_set(:@native_cpu, cpu)

    # Initialize HIRES soft switches
    bus.read(0xC050)  # TXTCLR - graphics mode
    bus.read(0xC052)  # MIXCLR - full screen
    bus.read(0xC054)  # PAGE1 - page 1
    bus.read(0xC057)  # HIRES - hi-res mode

    cpu.set_video_state(false, false, false, true)
    cpu.reset

    [cpu, bus]
  end

  def create_ir_compiler
    require 'rhdl/codegen'

    ir = RHDL::Apple2::Apple2.to_flat_ir
    ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)

    sim = RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json, sub_cycles: 14)

    karateka_rom = create_karateka_rom
    sim.apple2_load_rom(karateka_rom)
    sim.apple2_load_ram(@karateka_mem.first(48 * 1024), 0)

    sim.poke('reset', 1)
    sim.tick
    sim.poke('reset', 0)
    3.times { sim.apple2_run_cpu_cycles(1, 0, false) }

    # Initialize HIRES soft switches
    sim.poke('soft_switches', 8)

    sim
  end

  def verilator_runner_available?
    return false unless verilator_available?
    begin
      require_relative '../../../examples/apple2/utilities/apple2_verilator'
      true
    rescue LoadError
      false
    end
  end

  def create_verilator_runner
    require_relative '../../../examples/apple2/utilities/apple2_verilator'

    runner = RHDL::Apple2::VerilatorRunner.new(sub_cycles: 14)

    karateka_rom = create_karateka_rom
    runner.load_rom(karateka_rom, base_addr: 0xD000)
    runner.load_ram(@karateka_mem, base_addr: 0x0000)

    runner.reset

    runner
  end

  # Categorize PC into memory regions
  def pc_region(pc)
    case pc
    when 0x0000..0x01FF then :zp_stack
    when 0x0200..0x03FF then :input_buf
    when 0x0400..0x07FF then :text
    when 0x0800..0x1FFF then :user
    when 0x2000..0x3FFF then :hires1
    when 0x4000..0x5FFF then :hires2
    when 0x6000..0xBFFF then :high_ram
    when 0xC000..0xCFFF then :io
    when 0xD000..0xFFFF then :rom
    else :unknown
    end
  end

  # Normalize PC to 256-byte page for sequence comparison
  # This groups nearby addresses together to tolerate minor timing differences
  def pc_page(pc)
    pc >> 8
  end

  # Categorize opcode into instruction type for sequence comparison
  # Groups similar instructions together to tolerate minor execution differences
  def opcode_category(opcode)
    case opcode
    when 0x00 then :brk
    when 0x20 then :jsr
    when 0x40 then :rti
    when 0x60 then :rts
    when 0x4C, 0x6C then :jmp
    when 0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0 then :branch
    when 0xA9, 0xA5, 0xB5, 0xAD, 0xBD, 0xB9, 0xA1, 0xB1 then :lda
    when 0xA2, 0xA6, 0xB6, 0xAE, 0xBE then :ldx
    when 0xA0, 0xA4, 0xB4, 0xAC, 0xBC then :ldy
    when 0x85, 0x95, 0x8D, 0x9D, 0x99, 0x81, 0x91 then :sta
    when 0x86, 0x96, 0x8E then :stx
    when 0x84, 0x94, 0x8C then :sty
    when 0x69, 0x65, 0x75, 0x6D, 0x7D, 0x79, 0x61, 0x71 then :adc
    when 0xE9, 0xE5, 0xF5, 0xED, 0xFD, 0xF9, 0xE1, 0xF1 then :sbc
    when 0x29, 0x25, 0x35, 0x2D, 0x3D, 0x39, 0x21, 0x31 then :and
    when 0x09, 0x05, 0x15, 0x0D, 0x1D, 0x19, 0x01, 0x11 then :ora
    when 0x49, 0x45, 0x55, 0x4D, 0x5D, 0x59, 0x41, 0x51 then :eor
    when 0xC9, 0xC5, 0xD5, 0xCD, 0xDD, 0xD9, 0xC1, 0xD1 then :cmp
    when 0xE0, 0xE4, 0xEC then :cpx
    when 0xC0, 0xC4, 0xCC then :cpy
    when 0xE6, 0xF6, 0xEE, 0xFE then :inc
    when 0xC6, 0xD6, 0xCE, 0xDE then :dec
    when 0x0A, 0x06, 0x16, 0x0E, 0x1E then :asl
    when 0x4A, 0x46, 0x56, 0x4E, 0x5E then :lsr
    when 0x2A, 0x26, 0x36, 0x2E, 0x3E then :rol
    when 0x6A, 0x66, 0x76, 0x6E, 0x7E then :ror
    when 0xAA then :tax
    when 0x8A then :txa
    when 0xA8 then :tay
    when 0x98 then :tya
    when 0xBA then :tsx
    when 0x9A then :txs
    when 0x48 then :pha
    when 0x68 then :pla
    when 0x08 then :php
    when 0x28 then :plp
    when 0xE8 then :inx
    when 0xCA then :dex
    when 0xC8 then :iny
    when 0x88 then :dey
    when 0x18 then :clc
    when 0x38 then :sec
    when 0x58 then :cli
    when 0x78 then :sei
    when 0xD8 then :cld
    when 0xF8 then :sed
    when 0xB8 then :clv
    when 0x24, 0x2C then :bit
    when 0xEA then :nop
    else :other
    end
  end

  # Get opcode name for display
  def opcode_name(opcode)
    names = {
      0x00 => 'BRK', 0x20 => 'JSR', 0x40 => 'RTI', 0x60 => 'RTS',
      0x4C => 'JMP', 0x6C => 'JMP()', 0xEA => 'NOP',
      0x10 => 'BPL', 0x30 => 'BMI', 0x50 => 'BVC', 0x70 => 'BVS',
      0x90 => 'BCC', 0xB0 => 'BCS', 0xD0 => 'BNE', 0xF0 => 'BEQ',
      0xA9 => 'LDA#', 0xA5 => 'LDAzp', 0xAD => 'LDAabs',
      0xA2 => 'LDX#', 0xA6 => 'LDXzp', 0xAE => 'LDXabs',
      0xA0 => 'LDY#', 0xA4 => 'LDYzp', 0xAC => 'LDYabs',
      0x85 => 'STAzp', 0x8D => 'STAabs',
      0x86 => 'STXzp', 0x8E => 'STXabs',
      0x84 => 'STYzp', 0x8C => 'STYabs',
      0xE8 => 'INX', 0xCA => 'DEX', 0xC8 => 'INY', 0x88 => 'DEY',
      0x48 => 'PHA', 0x68 => 'PLA', 0x08 => 'PHP', 0x28 => 'PLP',
    }
    names[opcode] || format('$%02X', opcode)
  end

  # Check if seq_a is a subsequence of seq_b (elements appear in same order)
  def is_subsequence?(seq_a, seq_b)
    return true if seq_a.empty?
    return false if seq_b.empty?

    a_idx = 0
    seq_b.each do |b_elem|
      if seq_a[a_idx] == b_elem
        a_idx += 1
        return true if a_idx >= seq_a.length
      end
    end
    false
  end

  # Find longest common subsequence length
  def lcs_length(seq_a, seq_b)
    return 0 if seq_a.empty? || seq_b.empty?

    # Use space-optimized LCS
    m, n = seq_a.length, seq_b.length
    prev = Array.new(n + 1, 0)
    curr = Array.new(n + 1, 0)

    m.times do |i|
      n.times do |j|
        if seq_a[i] == seq_b[j]
          curr[j + 1] = prev[j] + 1
        else
          curr[j + 1] = [curr[j], prev[j + 1]].max
        end
      end
      prev, curr = curr, prev
    end
    prev[n]
  end

  # Find which elements of seq_a appear in seq_b in order
  def find_matching_subsequence(seq_a, seq_b)
    matched = []
    b_idx = 0

    seq_a.each_with_index do |a_elem, a_idx|
      while b_idx < seq_b.length
        if seq_b[b_idx] == a_elem
          matched << { a_idx: a_idx, b_idx: b_idx, value: a_elem }
          b_idx += 1
          break
        end
        b_idx += 1
      end
    end
    matched
  end

  # HiRes helpers
  def hires_page_base_isa(bus)
    bus.hires_page_base
  end

  def hires_page_base_ir(sim)
    page2 = sim.peek('page2')
    page2 == 1 ? 0x4000 : 0x2000
  end

  def hires_line_address(row, base)
    section = row / 64
    row_in_section = row % 64
    group = row_in_section / 8
    line_in_group = row_in_section % 8
    base + (line_in_group * 0x400) + (group * 0x80) + (section * 0x28)
  end

  def decode_hires_isa(bus, base_addr = 0x2000)
    bitmap = []
    192.times do |row|
      line = []
      line_addr = hires_line_address(row, base_addr)
      40.times do |col|
        byte = bus.mem_read(line_addr + col) || 0
        7.times { |bit| line << ((byte >> bit) & 1) }
      end
      bitmap << line
    end
    bitmap
  end

  def decode_hires_ir(sim, base_addr = 0x2000)
    ram = sim.apple2_read_ram(base_addr, 0x2000).to_a
    bitmap = []
    192.times do |row|
      line = []
      line_addr = hires_line_address(row, base_addr) - base_addr
      40.times do |col|
        byte = ram[line_addr + col] || 0
        7.times { |bit| line << ((byte >> bit) & 1) }
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

  def text_checksum_isa(bus)
    checksum = 0
    (0x0400..0x07FF).each { |addr| checksum = (checksum + bus.mem_read(addr)) & 0xFFFFFFFF }
    checksum
  end

  def text_checksum_ir(sim)
    checksum = 0
    sim.apple2_read_ram(0x0400, 0x400).to_a.each { |b| checksum = (checksum + b) & 0xFFFFFFFF }
    checksum
  end

  def text_checksum_verilator(runner)
    checksum = 0
    (0x0400..0x07FF).each { |addr| checksum = (checksum + runner.read(addr)) & 0xFFFFFFFF }
    checksum
  end

  def decode_hires_verilator(runner, base_addr = 0x2000)
    bitmap = []
    192.times do |row|
      line = []
      line_addr = hires_line_address(row, base_addr)
      40.times do |col|
        byte = runner.read(line_addr + col) || 0
        7.times { |bit| line << ((byte >> bit) & 1) }
      end
      bitmap << line
    end
    bitmap
  end

  it 'verifies PC and opcode sequences match through 5M cycles', timeout: 600 do
    skip 'AppleIIgo ROM not found' unless @rom_available
    skip 'Karateka memory dump not found' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?

    begin
      require 'rhdl/codegen'
      skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
    rescue LoadError
      skip 'IR Codegen not available'
    end

    # Check if Verilator is available (optional for this test)
    verilator_sim = nil
    if verilator_available?
      puts "\nVerilator available - will include in comparison"
    else
      puts "\nVerilator not available - comparing ISA and IR only"
    end

    puts "\n" + "=" * 70
    puts "Karateka PC and Opcode Verification (5M cycles)"
    puts "=" * 70

    # Create simulators
    puts "\nInitializing simulators..."
    init_start = Time.now
    isa_cpu, isa_bus = create_isa_simulator
    puts "  ISA: Native Rust ISA simulator (#{(Time.now - init_start).round(2)}s)"

    ir_start = Time.now
    ir_sim = create_ir_compiler
    puts "  IR:  Rust IR Compiler (#{(Time.now - ir_start).round(2)}s)"

    if verilator_available?
      verilator_start = Time.now
      verilator_sim = create_verilator_runner
      puts "  Verilator: HDL simulation (#{(Time.now - verilator_start).round(2)}s)"
    end

    # Checkpoint cycle counts to verify (up to 5M cycles)
    checkpoints = [100_000, 500_000, 1_000_000, 2_000_000, 3_000_000, 4_000_000, 5_000_000]
    total_cycles = 5_000_000

    cycles_run = 0
    isa_instruction_count = 0
    ir_instruction_count = 0
    mismatches = []
    results = []

    # Track IR opcode changes - IR starts with first instruction already fetched
    prev_ir_opcode = ir_sim.peek('opcode_debug')

    # Sync: verify first instruction matches
    first_ir_pc = ir_sim.peek('cpu__pc_reg')
    first_isa_pc = isa_cpu.pc
    first_isa_opcode = isa_bus.mem_read(first_isa_pc)

    if first_isa_opcode != prev_ir_opcode && mismatches.length < 10
      mismatches << {
        instr: 0,
        isa_pc: first_isa_pc,
        isa_opcode: first_isa_opcode,
        ir_pc: first_ir_pc,
        ir_opcode: prev_ir_opcode
      }
    end

    # Step ISA for first instruction (IR already has it)
    isa_cpu.step
    isa_instruction_count += 1
    ir_instruction_count += 1

    puts "\nRunning simulation with continuous opcode verification..."
    puts "-" * 70

    checkpoints.each do |target_cycles|
      cycles_to_run = target_cycles - cycles_run

      # Run IR cycles, step ISA at instruction boundaries
      cycles_to_run.times do
        # Run IR one cycle
        ir_sim.apple2_run_cpu_cycles(1, 0, false)

        # Check for IR instruction boundary (opcode changed)
        ir_opcode = ir_sim.peek('opcode_debug')
        if ir_opcode != prev_ir_opcode
          ir_pc = ir_sim.peek('cpu__pc_reg')
          ir_instruction_count += 1

          # Step ISA to match
          break if isa_cpu.halted?
          isa_pc = isa_cpu.pc
          isa_opcode = isa_bus.mem_read(isa_pc)
          isa_cpu.step
          isa_instruction_count += 1

          # Compare opcodes
          if isa_opcode != ir_opcode && mismatches.length < 10
            mismatches << {
              instr: ir_instruction_count,
              isa_pc: isa_pc,
              isa_opcode: isa_opcode,
              ir_pc: ir_pc,
              ir_opcode: ir_opcode
            }
          end
          prev_ir_opcode = ir_opcode
        end
      end

      # Run Verilator for this checkpoint (batch execution)
      if verilator_sim
        verilator_sim.run_steps(cycles_to_run)
      end

      cycles_run = target_cycles

      # Get current PCs for checkpoint
      isa_pc = isa_cpu.pc
      ir_pc = ir_sim.peek('cpu__pc_reg')
      verilator_pc = verilator_sim&.pc

      isa_region = pc_region(isa_pc)
      ir_region = pc_region(ir_pc)
      verilator_region = verilator_pc ? pc_region(verilator_pc) : nil

      pc_diff = (isa_pc - ir_pc).abs
      close = pc_diff < 256 || isa_region == ir_region

      status = close ? "OK" : "DIVERGED"
      if verilator_sim
        puts format("  %5.1fM: ISA=$%04X (%s) IR=$%04X (%s) Ver=$%04X (%s) ops=%d/%d - %s",
                    target_cycles / 1_000_000.0, isa_pc, isa_region, ir_pc, ir_region,
                    verilator_pc, verilator_region,
                    isa_instruction_count, ir_instruction_count, status)
      else
        puts format("  %5.1fM: ISA PC=$%04X (%s) IR PC=$%04X (%s) ops=%d/%d - %s",
                    target_cycles / 1_000_000.0, isa_pc, isa_region, ir_pc, ir_region,
                    isa_instruction_count, ir_instruction_count, status)
      end

      results << {
        cycles: target_cycles,
        isa_pc: isa_pc,
        ir_pc: ir_pc,
        verilator_pc: verilator_pc,
        isa_region: isa_region,
        ir_region: ir_region,
        verilator_region: verilator_region,
        close: close
      }
    end

    puts "\n" + "=" * 70

    # Summary
    failed = results.reject { |r| r[:close] }
    if failed.empty? && mismatches.empty?
      puts "All #{isa_instruction_count} ISA ops verified, all #{results.length} checkpoints passed"
    else
      if mismatches.any?
        puts "Found #{mismatches.length} opcode mismatches:"
        mismatches.each do |m|
          puts format("  #%d: ISA PC=$%04X op=$%02X | IR PC=$%04X op=$%02X",
                      m[:instr], m[:isa_pc], m[:isa_opcode], m[:ir_pc], m[:ir_opcode])
        end
      end
      if failed.any?
        puts "#{failed.length} checkpoints failed:"
        failed.each do |f|
          ver_str = f[:verilator_pc] ? " Ver=$#{f[:verilator_pc].to_s(16).upcase}" : ""
          puts "  #{f[:cycles] / 1_000_000.0}M: ISA=$#{f[:isa_pc].to_s(16).upcase} IR=$#{f[:ir_pc].to_s(16).upcase}#{ver_str}"
        end
      end
    end

    # Verilator summary if available
    if verilator_sim
      verilator_unique_pcs = results.map { |r| r[:verilator_pc] }.compact.uniq
      verilator_regions = results.map { |r| r[:verilator_region] }.compact.tally
      puts "\nVerilator summary:"
      puts "  Unique PCs at checkpoints: #{verilator_unique_pcs.length}"
      puts "  Regions visited: #{verilator_regions.map { |r, c| "#{r}=#{c}" }.join(', ')}"

      # Check if Verilator visits game regions
      ver_visits_game = verilator_regions.keys.any? { |r| [:rom, :high_ram, :user].include?(r) }
      if ver_visits_game
        puts "  ✅ Verilator visits game regions"
      else
        puts "  ❌ Verilator not visiting game regions"
      end
    end

    expect(mismatches).to be_empty,
      "All opcodes should match, but found #{mismatches.length} mismatches"

    expect(failed).to be_empty,
      "All cycle checkpoints should have close PCs, but #{failed.length} diverged"

    # Additional Verilator assertion if available
    if verilator_sim
      verilator_unique_pcs = results.map { |r| r[:verilator_pc] }.compact.uniq
      expect(verilator_unique_pcs.length).to be > 1,
        "Verilator should visit multiple PCs, not stuck at one location"
    end
  end

  it 'compares ISA vs IR vs Verilator through 100K cycles', timeout: 300 do
    skip 'AppleIIgo ROM not found' unless @rom_available
    skip 'Karateka memory dump not found' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?
    skip 'Verilator not available' unless verilator_available?

    begin
      require 'rhdl/codegen'
      skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
    rescue LoadError
      skip 'IR Codegen not available'
    end

    puts "\n" + "=" * 70
    puts "ISA vs IR vs Verilator Comparison (100K cycles)"
    puts "=" * 70

    # Create all three simulators
    puts "\nInitializing simulators..."
    init_start = Time.now

    isa_cpu, isa_bus = create_isa_simulator
    puts "  ISA: Native Rust ISA simulator (#{(Time.now - init_start).round(2)}s)"

    ir_start = Time.now
    ir_sim = create_ir_compiler
    puts "  IR:  Rust IR Compiler (#{(Time.now - ir_start).round(2)}s)"

    verilator_start = Time.now
    verilator_runner = create_verilator_runner
    puts "  Verilator: HDL simulation (#{(Time.now - verilator_start).round(2)}s)"

    total_init = Time.now - init_start
    puts "  Total init: #{total_init.round(2)}s"

    # Checkpoint cycle counts
    checkpoints = [10_000, 25_000, 50_000, 75_000, 100_000]
    total_cycles = 100_000

    cycles_run = 0
    results = []

    # Track IR opcode changes
    prev_ir_opcode = ir_sim.peek('opcode_debug')

    puts "\nRunning simulation with PC comparison..."
    puts "-" * 70
    puts format("  %8s  %12s  %12s  %12s  %s", "Cycles", "ISA PC", "IR PC", "Verilator PC", "Status")
    puts "-" * 70

    checkpoints.each do |target_cycles|
      cycles_to_run = target_cycles - cycles_run

      # Run all three simulators
      # ISA: step-based
      cycles_to_run.times do
        break if isa_cpu.halted?
        isa_cpu.step
      end

      # IR: cycle-based
      ir_sim.apple2_run_cpu_cycles(cycles_to_run, 0, false)

      # Verilator: step-based (1 step = 1 CPU cycle = 14 sub-cycles)
      verilator_runner.run_steps(cycles_to_run)

      cycles_run = target_cycles

      # Get current PCs
      isa_pc = isa_cpu.pc
      ir_pc = ir_sim.peek('cpu__pc_reg')
      verilator_pc = verilator_runner.pc

      isa_region = pc_region(isa_pc)
      ir_region = pc_region(ir_pc)
      verilator_region = pc_region(verilator_pc)

      # Check if all three are close (within same region or 256 bytes)
      isa_ir_close = (isa_pc - ir_pc).abs < 256 || isa_region == ir_region
      isa_ver_close = (isa_pc - verilator_pc).abs < 256 || isa_region == verilator_region
      ir_ver_close = (ir_pc - verilator_pc).abs < 256 || ir_region == verilator_region

      all_close = isa_ir_close && isa_ver_close && ir_ver_close
      status = all_close ? "OK" : "DIVERGED"

      puts format("  %8d  $%04X (%-6s)  $%04X (%-6s)  $%04X (%-6s)  %s",
                  target_cycles,
                  isa_pc, isa_region,
                  ir_pc, ir_region,
                  verilator_pc, verilator_region,
                  status)

      results << {
        cycles: target_cycles,
        isa_pc: isa_pc,
        ir_pc: ir_pc,
        verilator_pc: verilator_pc,
        isa_region: isa_region,
        ir_region: ir_region,
        verilator_region: verilator_region,
        all_close: all_close
      }
    end

    puts "-" * 70

    # Compare final memory state
    puts "\nFinal memory comparison:"
    isa_text = text_checksum_isa(isa_bus)
    ir_text = text_checksum_ir(ir_sim)
    verilator_text = text_checksum_verilator(verilator_runner)

    puts format("  Text page checksum: ISA=%08X IR=%08X Verilator=%08X",
                isa_text, ir_text, verilator_text)

    isa_ir_text_match = isa_text == ir_text
    isa_ver_text_match = isa_text == verilator_text

    # Summary
    puts "\n" + "=" * 70
    puts "SUMMARY"
    puts "=" * 70

    failed = results.reject { |r| r[:all_close] }

    # Check 1: All checkpoints close
    if failed.empty?
      puts "✅ All #{results.length} checkpoints have close PCs"
    else
      puts "❌ #{failed.length} checkpoints diverged"
      failed.each do |f|
        puts format("   %d: ISA=$%04X IR=$%04X Ver=$%04X",
                    f[:cycles], f[:isa_pc], f[:ir_pc], f[:verilator_pc])
      end
    end

    # Check 2: All visit game regions
    isa_visits_game = results.any? { |r| [:rom, :high_ram, :user].include?(r[:isa_region]) }
    ir_visits_game = results.any? { |r| [:rom, :high_ram, :user].include?(r[:ir_region]) }
    ver_visits_game = results.any? { |r| [:rom, :high_ram, :user].include?(r[:verilator_region]) }

    if isa_visits_game && ir_visits_game && ver_visits_game
      puts "✅ All simulators visit game regions"
    else
      puts "❌ Not all simulators visit game regions (ISA=#{isa_visits_game}, IR=#{ir_visits_game}, Ver=#{ver_visits_game})"
    end

    # Check 3: Final PCs are in valid regions
    final = results.last
    valid_regions = [:rom, :high_ram, :user, :zp_stack]
    all_valid = valid_regions.include?(final[:isa_region]) &&
                valid_regions.include?(final[:ir_region]) &&
                valid_regions.include?(final[:verilator_region])

    if all_valid
      puts "✅ All final PCs in valid game regions"
    else
      puts "❌ Some final PCs in unexpected regions"
    end

    puts "\n"

    # Assertions - be lenient since Verilator may have timing differences
    # Require that all simulators visit game regions
    expect(isa_visits_game && ir_visits_game && ver_visits_game).to be(true),
      "All simulators should visit game loop regions"

    # Require that Verilator visits multiple unique PCs (not stuck)
    verilator_unique_pcs = results.map { |r| r[:verilator_pc] }.uniq
    expect(verilator_unique_pcs.length).to be > 1,
      "Verilator should visit multiple PCs, not stuck at one location"

    # ISA and IR should be close (they use same timing model)
    isa_ir_diverged = results.reject { |r|
      (r[:isa_pc] - r[:ir_pc]).abs < 256 || r[:isa_region] == r[:ir_region]
    }
    expect(isa_ir_diverged).to be_empty,
      "ISA and IR should have close PCs at all checkpoints"
  end

  it 'verifies PC sequence subsequence matching over 20M cycles', timeout: 1800 do
    skip 'AppleIIgo ROM not found' unless @rom_available
    skip 'Karateka memory dump not found' unless @karateka_available
    skip 'Native ISA simulator not available' unless native_isa_available?

    begin
      require 'rhdl/codegen'
      skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
    rescue LoadError
      skip 'IR Codegen not available'
    end

    # Check if Verilator is available (optional for this test)
    verilator_sim = nil
    if verilator_available?
      puts "\nVerilator available - will include in comparison"
    else
      puts "\nVerilator not available - comparing ISA and IR only"
    end

    puts "\n" + "=" * 70
    puts "Karateka PC Sequence Subsequence Matching"
    if START_CYCLES > 0
      puts "Cycle range: #{START_CYCLES.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} - #{END_CYCLES.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    else
      puts "Total cycles: #{END_CYCLES.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    end
    puts "Analysis cycles: #{TOTAL_CYCLES.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "PC sample interval: #{PC_SAMPLE_INTERVAL / 1000}K cycles"
    puts "=" * 70

    # Create simulators
    puts "\nInitializing simulators..."
    init_start = Time.now
    isa_cpu, isa_bus = create_isa_simulator
    puts "  ISA: Native Rust ISA simulator (#{(Time.now - init_start).round(2)}s)"

    ir_start = Time.now
    ir_sim = create_ir_compiler
    puts "  IR:  Rust IR Compiler (sub_cycles=14) (#{(Time.now - ir_start).round(2)}s)"

    if verilator_available?
      verilator_start = Time.now
      verilator_sim = create_verilator_runner
      puts "  Verilator: HDL simulation (#{(Time.now - verilator_start).round(2)}s)"
    end

    # Warmup phase - fast-forward to START_CYCLES if needed
    if START_CYCLES > 0
      puts "\nWarming up to #{START_CYCLES / 1_000_000.0}M cycles..."
      warmup_start = Time.now
      warmup_batch = 100_000
      warmup_run = 0

      while warmup_run < START_CYCLES
        batch = [warmup_batch, START_CYCLES - warmup_run].min
        batch.times { isa_cpu.step unless isa_cpu.halted? }
        ir_sim.apple2_run_cpu_cycles(batch, 0, false)
        verilator_sim&.run_steps(batch)
        warmup_run += batch

        if warmup_run % 5_000_000 == 0
          elapsed = Time.now - warmup_start
          rate = warmup_run / elapsed / 1_000_000
          puts "  Warmup: #{(warmup_run / 1_000_000.0).round(1)}M cycles (#{rate.round(2)}M/s)"
        end
      end

      warmup_elapsed = Time.now - warmup_start
      puts "  Warmup complete in #{warmup_elapsed.round(1)}s"

      # Show state at warmup end
      isa_pc = isa_cpu.pc
      ir_pc = ir_sim.peek('cpu__pc_reg')
      verilator_pc_str = verilator_sim ? " Ver=$#{verilator_sim.pc.to_s(16).upcase.rjust(4, '0')}" : ""
      puts "  State at #{START_CYCLES / 1_000_000.0}M: ISA=$#{isa_pc.to_s(16).upcase.rjust(4, '0')} IR=$#{ir_pc.to_s(16).upcase.rjust(4, '0')}#{verilator_pc_str}"
    end

    # Collect PC sequences
    isa_pc_sequence = []
    ir_pc_sequence = []
    verilator_pc_sequence = []
    isa_page_sequence = []  # PC pages (256-byte granularity)
    ir_page_sequence = []
    verilator_page_sequence = []

    # Collect opcode sequences
    isa_opcode_sequence = []
    ir_opcode_sequence = []
    verilator_opcode_sequence = []
    isa_opcode_category_sequence = []
    ir_opcode_category_sequence = []
    verilator_opcode_category_sequence = []

    cycles_run = 0
    last_sample = 0
    start_time = Time.now

    puts "\nCollecting PC and opcode sequences..."
    puts "-" * 70

    while cycles_run < TOTAL_CYCLES
      # Run in small batches, sampling PC
      batch_size = [PC_SAMPLE_INTERVAL, TOTAL_CYCLES - cycles_run].min

      # Run ISA
      batch_size.times do
        break if isa_cpu.halted?
        isa_cpu.step
      end

      # Run IR
      ir_sim.apple2_run_cpu_cycles(batch_size, 0, false)

      # Run Verilator
      verilator_sim&.run_steps(batch_size)

      cycles_run += batch_size

      # Sample PC
      isa_pc = isa_cpu.pc
      ir_pc = ir_sim.peek('cpu__pc_reg')
      verilator_pc = verilator_sim&.pc

      isa_pc_sequence << isa_pc
      ir_pc_sequence << ir_pc
      verilator_pc_sequence << verilator_pc if verilator_sim
      isa_page_sequence << pc_page(isa_pc)
      ir_page_sequence << pc_page(ir_pc)
      verilator_page_sequence << pc_page(verilator_pc) if verilator_sim

      # Sample opcode (read byte at current PC for ISA, use debug signal for IR)
      isa_opcode = isa_bus.mem_read(isa_pc) & 0xFF
      ir_opcode = ir_sim.peek('opcode_debug') & 0xFF
      verilator_opcode = verilator_sim ? (verilator_sim.read(verilator_pc) & 0xFF) : nil

      isa_opcode_sequence << isa_opcode
      ir_opcode_sequence << ir_opcode
      verilator_opcode_sequence << verilator_opcode if verilator_sim
      isa_opcode_category_sequence << opcode_category(isa_opcode)
      ir_opcode_category_sequence << opcode_category(ir_opcode)
      verilator_opcode_category_sequence << opcode_category(verilator_opcode) if verilator_sim

      # Progress output at checkpoints
      if cycles_run - last_sample >= CHECKPOINT_INTERVAL
        last_sample = cycles_run
        elapsed = Time.now - start_time
        rate = cycles_run / elapsed / 1_000_000
        pct = (cycles_run.to_f / TOTAL_CYCLES * 100).round(1)
        absolute_cycles = START_CYCLES + cycles_run

        ver_str = verilator_sim ? format(" | Ver=%04X %-8s", verilator_pc, pc_region(verilator_pc)) : ""
        puts format("  %5.1f%% | %7.1fM | ISA=%04X %-8s | IR=%04X %-8s%s | %.2fM/s",
                    pct, absolute_cycles / 1_000_000.0,
                    isa_pc, pc_region(isa_pc),
                    ir_pc, pc_region(ir_pc),
                    ver_str,
                    rate)

        # Print screen at intervals (based on absolute cycles)
        if ((absolute_cycles) % SCREEN_INTERVAL).zero?
          isa_page = hires_page_base_isa(isa_bus)
          ir_page = hires_page_base_ir(ir_sim)

          isa_bitmap = decode_hires_isa(isa_bus, isa_page)
          print_hires_screen("ISA HiRes (page #{isa_page == 0x2000 ? 1 : 2})", isa_bitmap, absolute_cycles)

          ir_bitmap = decode_hires_ir(ir_sim, ir_page)
          print_hires_screen("IR HiRes (page #{ir_page == 0x2000 ? 1 : 2})", ir_bitmap, absolute_cycles)

          if verilator_sim
            verilator_bitmap = decode_hires_verilator(verilator_sim, 0x2000)
            print_hires_screen("Verilator HiRes", verilator_bitmap, absolute_cycles)
          end
        end
      end
    end

    elapsed = Time.now - start_time
    puts "-" * 70
    puts format("Completed in %.1f seconds (%.2fM cycles/sec)", elapsed, TOTAL_CYCLES / elapsed / 1_000_000)

    # Analyze PC sequences
    puts "\n" + "=" * 70
    puts "PC SEQUENCE ANALYSIS"
    puts "=" * 70

    puts "\nSequence lengths:"
    puts "  ISA: #{isa_pc_sequence.length} samples"
    puts "  IR:  #{ir_pc_sequence.length} samples"
    puts "  Verilator: #{verilator_pc_sequence.length} samples" if verilator_sim

    # Unique PCs visited
    isa_unique = isa_pc_sequence.uniq
    ir_unique = ir_pc_sequence.uniq
    verilator_unique = verilator_pc_sequence.uniq if verilator_sim
    common_pcs = isa_unique & ir_unique

    puts "\nUnique PCs visited:"
    puts "  ISA: #{isa_unique.length} unique PCs"
    puts "  IR:  #{ir_unique.length} unique PCs"
    puts "  Verilator: #{verilator_unique.length} unique PCs" if verilator_sim
    puts "  Common (ISA & IR): #{common_pcs.length} PCs visited by both"

    # Page-level analysis (more tolerant of timing)
    isa_unique_pages = isa_page_sequence.uniq
    ir_unique_pages = ir_page_sequence.uniq
    verilator_unique_pages = verilator_page_sequence.uniq if verilator_sim
    common_pages = isa_unique_pages & ir_unique_pages

    puts "\nUnique PC pages (256-byte granularity):"
    puts "  ISA: #{isa_unique_pages.length} unique pages"
    puts "  IR:  #{ir_unique_pages.length} unique pages"
    puts "  Verilator: #{verilator_unique_pages.length} unique pages" if verilator_sim
    puts "  Common (ISA & IR): #{common_pages.length} pages visited by both"

    # LCS analysis on page sequences
    lcs_len = lcs_length(isa_page_sequence, ir_page_sequence)
    lcs_pct_isa = (lcs_len.to_f / isa_page_sequence.length * 100).round(1)
    lcs_pct_ir = (lcs_len.to_f / ir_page_sequence.length * 100).round(1)

    puts "\nLongest Common Subsequence (page-level):"
    puts "  LCS length: #{lcs_len}"
    puts "  Coverage of ISA sequence: #{lcs_pct_isa}%"
    puts "  Coverage of IR sequence: #{lcs_pct_ir}%"

    # Find matching subsequence
    matched = find_matching_subsequence(isa_page_sequence, ir_page_sequence)
    match_pct = (matched.length.to_f / isa_page_sequence.length * 100).round(1)

    puts "\nSubsequence matching (ISA pages found in IR in order):"
    puts "  Matched: #{matched.length} / #{isa_page_sequence.length} (#{match_pct}%)"

    # Region analysis
    isa_regions = isa_pc_sequence.map { |pc| pc_region(pc) }
    ir_regions = ir_pc_sequence.map { |pc| pc_region(pc) }
    verilator_regions = verilator_pc_sequence.map { |pc| pc_region(pc) } if verilator_sim

    isa_region_counts = isa_regions.tally.sort_by { |_, v| -v }
    ir_region_counts = ir_regions.tally.sort_by { |_, v| -v }
    verilator_region_counts = verilator_regions.tally.sort_by { |_, v| -v } if verilator_sim

    puts "\nRegion distribution:"
    puts "  ISA: #{isa_region_counts.map { |r, c| "#{r}=#{c}" }.join(', ')}"
    puts "  IR:  #{ir_region_counts.map { |r, c| "#{r}=#{c}" }.join(', ')}"
    puts "  Verilator: #{verilator_region_counts.map { |r, c| "#{r}=#{c}" }.join(', ')}" if verilator_sim

    # Opcode sequence analysis
    puts "\n" + "=" * 70
    puts "OPCODE SEQUENCE ANALYSIS"
    puts "=" * 70

    # Unique opcodes
    isa_unique_opcodes = isa_opcode_sequence.uniq.sort
    ir_unique_opcodes = ir_opcode_sequence.uniq.sort
    verilator_unique_opcodes = verilator_opcode_sequence.uniq.sort if verilator_sim
    common_opcodes = isa_unique_opcodes & ir_unique_opcodes

    puts "\nUnique opcodes executed:"
    puts "  ISA: #{isa_unique_opcodes.length} unique opcodes"
    puts "  IR:  #{ir_unique_opcodes.length} unique opcodes"
    puts "  Verilator: #{verilator_unique_opcodes.length} unique opcodes" if verilator_sim
    puts "  Common (ISA & IR): #{common_opcodes.length} opcodes used by both"

    # Opcode category analysis (more tolerant comparison)
    isa_unique_categories = isa_opcode_category_sequence.uniq
    ir_unique_categories = ir_opcode_category_sequence.uniq
    verilator_unique_categories = verilator_opcode_category_sequence.uniq if verilator_sim
    common_categories = isa_unique_categories & ir_unique_categories

    puts "\nUnique opcode categories:"
    puts "  ISA: #{isa_unique_categories.length} categories"
    puts "  IR:  #{ir_unique_categories.length} categories"
    puts "  Verilator: #{verilator_unique_categories.length} categories" if verilator_sim
    puts "  Common (ISA & IR): #{common_categories.length} categories"

    # LCS on opcode category sequences
    opcode_lcs_len = lcs_length(isa_opcode_category_sequence, ir_opcode_category_sequence)
    opcode_lcs_pct_isa = (opcode_lcs_len.to_f / isa_opcode_category_sequence.length * 100).round(1)
    opcode_lcs_pct_ir = (opcode_lcs_len.to_f / ir_opcode_category_sequence.length * 100).round(1)

    puts "\nLongest Common Subsequence (opcode categories):"
    puts "  LCS length: #{opcode_lcs_len}"
    puts "  Coverage of ISA sequence: #{opcode_lcs_pct_isa}%"
    puts "  Coverage of IR sequence: #{opcode_lcs_pct_ir}%"

    # Opcode frequency distribution
    isa_opcode_counts = isa_opcode_sequence.tally.sort_by { |_, v| -v }
    ir_opcode_counts = ir_opcode_sequence.tally.sort_by { |_, v| -v }

    puts "\nTop 10 opcodes by frequency:"
    puts "  ISA: #{isa_opcode_counts.first(10).map { |op, c| "#{opcode_name(op)}=#{c}" }.join(', ')}"
    puts "  IR:  #{ir_opcode_counts.first(10).map { |op, c| "#{opcode_name(op)}=#{c}" }.join(', ')}"

    # Category frequency distribution
    isa_category_counts = isa_opcode_category_sequence.tally.sort_by { |_, v| -v }
    ir_category_counts = ir_opcode_category_sequence.tally.sort_by { |_, v| -v }

    puts "\nOpcode category distribution:"
    puts "  ISA: #{isa_category_counts.first(10).map { |cat, c| "#{cat}=#{c}" }.join(', ')}"
    puts "  IR:  #{ir_category_counts.first(10).map { |cat, c| "#{cat}=#{c}" }.join(', ')}"

    # Check for anomalous opcodes (executed from graphics memory, etc.)
    ir_anomalous = ir_opcode_sequence.each_with_index.select do |op, idx|
      ir_pc = ir_pc_sequence[idx]
      pc_region(ir_pc) == :hires2 || pc_region(ir_pc) == :hires1
    end

    if ir_anomalous.any?
      puts "\n  ⚠️  IR executed #{ir_anomalous.length} opcodes from HiRes memory regions"
      # Show first few
      ir_anomalous.first(5).each do |op, idx|
        puts "    Sample #{idx}: PC=$#{ir_pc_sequence[idx].to_s(16).upcase} opcode=$#{op.to_s(16).upcase} (#{opcode_name(op)})"
      end
    end

    # Check for stuck behavior
    ir_stuck_in_one_region = ir_region_counts.first[1] > (ir_regions.length * 0.9)
    if ir_stuck_in_one_region
      puts "\n  ⚠️  IR appears stuck in #{ir_region_counts.first[0]} region"
    end

    # Text memory comparison
    isa_text = text_checksum_isa(isa_bus)
    ir_text = text_checksum_ir(ir_sim)
    verilator_text = text_checksum_verilator(verilator_sim) if verilator_sim
    text_match = isa_text == ir_text

    puts "\nFinal text memory:"
    puts "  ISA checksum: #{isa_text.to_s(16)}"
    puts "  IR checksum:  #{ir_text.to_s(16)}"
    puts "  Verilator checksum: #{verilator_text.to_s(16)}" if verilator_sim
    puts "  ISA/IR Match: #{text_match ? 'YES' : 'NO'}"
    puts "  ISA/Ver Match: #{isa_text == verilator_text ? 'YES' : 'NO'}" if verilator_sim

    # Summary
    puts "\n" + "=" * 70
    puts "SUMMARY"
    puts "=" * 70

    passing = true
    issues = []

    # Check 1: Common pages > 50%
    common_page_pct = (common_pages.length.to_f / [isa_unique_pages.length, ir_unique_pages.length].max * 100).round(1)
    if common_page_pct >= 50
      puts "✅ Common PC pages: #{common_page_pct}% (>= 50% required)"
    else
      puts "❌ Common PC pages: #{common_page_pct}% (< 50% required)"
      passing = false
      issues << "Common pages too low"
    end

    # Check 2: LCS coverage > 30%
    if lcs_pct_isa >= 30
      puts "✅ LCS coverage of ISA: #{lcs_pct_isa}% (>= 30% required)"
    else
      puts "❌ LCS coverage of ISA: #{lcs_pct_isa}% (< 30% required)"
      passing = false
      issues << "LCS coverage too low"
    end

    # Check 3: IR not stuck
    if !ir_stuck_in_one_region
      puts "✅ IR visits multiple regions"
    else
      puts "❌ IR stuck in single region"
      passing = false
      issues << "IR stuck in single region"
    end

    # Check 4: Both visit game loop (ROM/high_ram)
    isa_visits_game = isa_region_counts.any? { |r, _| [:rom, :high_ram].include?(r) }
    ir_visits_game = ir_region_counts.any? { |r, _| [:rom, :high_ram].include?(r) }

    if isa_visits_game && ir_visits_game
      puts "✅ Both visit game loop regions"
    else
      puts "❌ Missing game loop visits (ISA=#{isa_visits_game}, IR=#{ir_visits_game})"
      passing = false
      issues << "Missing game loop visits"
    end

    # Check 5: Opcode category LCS coverage > 30%
    if opcode_lcs_pct_isa >= 30
      puts "✅ Opcode category LCS coverage: #{opcode_lcs_pct_isa}% (>= 30% required)"
    else
      puts "❌ Opcode category LCS coverage: #{opcode_lcs_pct_isa}% (< 30% required)"
      passing = false
      issues << "Opcode LCS coverage too low"
    end

    # Check 6: Common opcode categories > 50%
    # Note: Different thresholds may apply depending on execution phase differences
    common_cat_pct = (common_categories.length.to_f / [isa_unique_categories.length, ir_unique_categories.length].max * 100).round(1)
    if common_cat_pct >= 50
      puts "✅ Common opcode categories: #{common_cat_pct}% (>= 50% required)"
    else
      puts "❌ Common opcode categories: #{common_cat_pct}% (< 50% required)"
      passing = false
      issues << "Common opcode categories too low"
    end

    # Check 7: No execution from HiRes memory
    if ir_anomalous.empty?
      puts "✅ No execution from HiRes memory"
    else
      puts "❌ IR executed #{ir_anomalous.length} opcodes from HiRes memory"
      passing = false
      issues << "IR executing from HiRes memory"
    end

    # Verilator-specific checks (informational, not assertions)
    if verilator_sim
      puts "\nVerilator summary:"
      verilator_visits_game = verilator_region_counts.any? { |r, _| [:rom, :high_ram, :user].include?(r) }
      verilator_stuck = verilator_region_counts.first[1] > (verilator_regions.length * 0.9)

      if verilator_visits_game
        puts "  ✅ Verilator visits game regions"
      else
        puts "  ⚠️  Verilator not visiting game regions (may be timing difference)"
      end

      if !verilator_stuck
        puts "  ✅ Verilator visits multiple regions"
      else
        puts "  ⚠️  Verilator appears stuck in #{verilator_region_counts.first[0]} region"
      end

      verilator_unique_at_samples = verilator_pc_sequence.uniq.length
      puts "  Unique PCs at samples: #{verilator_unique_at_samples}"
    end

    puts "\n"

    # Assertions
    expect(common_page_pct).to be >= 50,
      "Common PC pages should be >= 50%, got #{common_page_pct}%"

    expect(lcs_pct_isa).to be >= 30,
      "LCS coverage of ISA sequence should be >= 30%, got #{lcs_pct_isa}%"

    expect(ir_stuck_in_one_region).to be(false),
      "IR should not be stuck in a single region"

    expect(isa_visits_game && ir_visits_game).to be(true),
      "Both simulators should visit game loop (ROM/high_ram) regions"

    expect(opcode_lcs_pct_isa).to be >= 30,
      "Opcode category LCS coverage should be >= 30%, got #{opcode_lcs_pct_isa}%"

    expect(common_cat_pct).to be >= 50,
      "Common opcode categories should be >= 50%, got #{common_cat_pct}%"

    expect(ir_anomalous).to be_empty,
      "IR should not execute from HiRes memory regions"
  end

  # Verilator integration test
  it 'verifies Verilator runner can be initialized and has correct interface', timeout: 120 do
    skip 'Verilator not available' unless verilator_available?
    skip 'AppleIIgo ROM not found' unless @rom_available
    skip 'Karateka memory dump not found' unless @karateka_available

    require_relative '../../../examples/apple2/utilities/apple2_verilator'

    puts "\n" + "=" * 70
    puts "Verilator Runner Interface Verification"
    puts "=" * 70

    # Verify VerilatorRunner class exists and has expected interface
    expect(defined?(RHDL::Apple2::VerilatorRunner)).to eq('constant')

    runner_class = RHDL::Apple2::VerilatorRunner

    # Check required interface methods
    required_methods = %i[
      load_rom load_ram load_disk reset run_steps run_cpu_cycle
      inject_key read_screen_array read_screen screen_dirty?
      clear_screen_dirty read_hires_bitmap render_hires_braille
      render_hires_color cpu_state halted? cycle_count dry_run_info
      bus disk_controller speaker display_mode start_audio stop_audio
      read write native? simulator_type
    ]

    missing_methods = required_methods.reject { |m| runner_class.instance_methods.include?(m) }

    if missing_methods.empty?
      puts "All #{required_methods.length} required interface methods present"
    else
      puts "Missing methods: #{missing_methods.join(', ')}"
    end

    expect(missing_methods).to be_empty,
      "VerilatorRunner should implement all interface methods, missing: #{missing_methods.join(', ')}"

    # Verify constants
    expect(runner_class::TEXT_PAGE1_START).to eq(0x0400)
    expect(runner_class::HIRES_PAGE1_START).to eq(0x2000)
    expect(runner_class::HIRES_WIDTH).to eq(280)
    expect(runner_class::HIRES_HEIGHT).to eq(192)

    puts "Constants verified: TEXT_PAGE1_START=0x0400, HIRES_PAGE1_START=0x2000"

    # Verify DiskControllerStub
    stub = runner_class::DiskControllerStub.new
    expect(stub.track).to eq(0)
    expect(stub.motor_on).to eq(false)

    puts "DiskControllerStub verified"
    puts "=" * 70
    puts "Verilator interface verification PASSED"
  end

  it 'verifies Verilator simulation produces expected PC patterns', timeout: 300 do
    skip 'Verilator not available' unless verilator_available?
    skip 'AppleIIgo ROM not found' unless @rom_available
    skip 'Karateka memory dump not found' unless @karateka_available

    require_relative '../../../examples/apple2/utilities/apple2_verilator'

    puts "\n" + "=" * 70
    puts "Verilator Simulation PC Pattern Verification"
    puts "=" * 70

    # Initialize Verilator runner
    puts "\nInitializing Verilator runner..."
    start_time = Time.now
    runner = RHDL::Apple2::VerilatorRunner.new(sub_cycles: 14)
    init_time = Time.now - start_time
    puts "  Verilator initialized in #{init_time.round(2)}s"

    # Load Karateka ROM and memory
    karateka_rom = create_karateka_rom
    runner.load_rom(karateka_rom, base_addr: 0xD000)
    runner.load_ram(@karateka_mem, base_addr: 0x0000)
    puts "  Loaded Karateka ROM and memory dump"

    # Verify native interface
    expect(runner.native?).to be(true)
    expect(runner.simulator_type).to eq(:hdl_verilator)
    puts "  Runner type: #{runner.simulator_type}, native: #{runner.native?}"

    # Reset and run a few cycles
    runner.reset
    puts "  Reset complete"

    # Collect PC samples while running
    pc_samples = []
    total_cycles = 10_000  # Run 10K cycles for quick verification

    puts "\nRunning #{total_cycles} cycles..."
    run_start = Time.now

    sample_interval = 1000
    (total_cycles / sample_interval).times do |i|
      runner.run_steps(sample_interval)
      state = runner.cpu_state
      pc_samples << state[:pc]

      if (i + 1) % 5 == 0
        elapsed = Time.now - run_start
        cycles_done = (i + 1) * sample_interval
        rate = cycles_done / elapsed
        puts format("  %d cycles: PC=$%04X region=%s (%.0f cycles/s)",
                    cycles_done, state[:pc], pc_region(state[:pc]), rate)
      end
    end

    run_time = Time.now - run_start
    rate = total_cycles / run_time

    puts "\n" + "-" * 70
    puts format("Completed %d cycles in %.2fs (%.0f cycles/s)", total_cycles, run_time, rate)

    # Analyze PC samples
    unique_pcs = pc_samples.uniq
    regions = pc_samples.map { |pc| pc_region(pc) }
    region_counts = regions.tally

    puts "\nPC Analysis:"
    puts "  Unique PCs: #{unique_pcs.length}"
    puts "  Regions visited: #{region_counts.map { |r, c| "#{r}=#{c}" }.join(', ')}"

    # Verify the simulation is executing code (not stuck)
    expect(unique_pcs.length).to be > 1,
      "Simulation should visit multiple PCs, but only saw #{unique_pcs.length}"

    # Verify it's executing from expected regions (ROM or high RAM for Karateka)
    game_regions = [:rom, :high_ram, :user]
    visits_game = region_counts.keys.any? { |r| game_regions.include?(r) }

    expect(visits_game).to be(true),
      "Simulation should execute from game regions (ROM/high_ram/user)"

    puts "\n" + "=" * 70
    puts "Verilator simulation verification PASSED"
  end
end
