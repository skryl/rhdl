# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/hdl/apple2'
require_relative '../../../examples/apple2/utilities/braille_renderer'

RSpec.describe 'Karateka ISA vs IR Compiler Divergence' do
  # Test verifies that ISA and IR simulators execute the same code paths
  # by checking that PC sequences match as subsequences (allowing timing drift)

  ROM_PATH = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  KARATEKA_MEM_PATH = File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

  # Test parameters
  TOTAL_CYCLES = 20_000_000
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
    sim.load_rom(karateka_rom)
    sim.load_ram(@karateka_mem.first(48 * 1024), 0)

    sim.poke('reset', 1)
    sim.tick
    sim.poke('reset', 0)
    3.times { sim.run_cpu_cycles(1, 0, false) }

    # Initialize HIRES soft switches
    sim.poke('soft_switches', 8)

    sim
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
    ram = sim.read_ram(base_addr, 0x2000).to_a
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
    sim.read_ram(0x0400, 0x400).to_a.each { |b| checksum = (checksum + b) & 0xFFFFFFFF }
    checksum
  end

  it 'verifies PC sequence subsequence matching over 20M cycles', timeout: 1200 do
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
    puts "Karateka PC Sequence Subsequence Matching"
    puts "Total cycles: #{TOTAL_CYCLES.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "PC sample interval: #{PC_SAMPLE_INTERVAL / 1000}K cycles"
    puts "=" * 70

    # Create simulators
    puts "\nInitializing simulators..."
    isa_cpu, isa_bus = create_isa_simulator
    ir_sim = create_ir_compiler

    puts "  ISA: Native Rust ISA simulator"
    puts "  IR:  Rust IR Compiler (sub_cycles=14)"

    # Collect PC sequences
    isa_pc_sequence = []
    ir_pc_sequence = []
    isa_page_sequence = []  # PC pages (256-byte granularity)
    ir_page_sequence = []

    cycles_run = 0
    last_sample = 0
    start_time = Time.now

    puts "\nCollecting PC sequences..."
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
      ir_sim.run_cpu_cycles(batch_size, 0, false)

      cycles_run += batch_size

      # Sample PC
      isa_pc = isa_cpu.pc
      ir_pc = ir_sim.peek('cpu__pc_reg')

      isa_pc_sequence << isa_pc
      ir_pc_sequence << ir_pc
      isa_page_sequence << pc_page(isa_pc)
      ir_page_sequence << pc_page(ir_pc)

      # Progress output at checkpoints
      if cycles_run - last_sample >= CHECKPOINT_INTERVAL
        last_sample = cycles_run
        elapsed = Time.now - start_time
        rate = cycles_run / elapsed / 1_000_000
        pct = (cycles_run.to_f / TOTAL_CYCLES * 100).round(1)

        puts format("  %5.1f%% | %7.1fM | ISA PC=%04X region=%-8s | IR PC=%04X region=%-8s | %.2fM/s",
                    pct, cycles_run / 1_000_000.0,
                    isa_pc, pc_region(isa_pc),
                    ir_pc, pc_region(ir_pc),
                    rate)

        # Print screen at intervals
        if (cycles_run % SCREEN_INTERVAL).zero?
          isa_page = hires_page_base_isa(isa_bus)
          ir_page = hires_page_base_ir(ir_sim)

          isa_bitmap = decode_hires_isa(isa_bus, isa_page)
          print_hires_screen("ISA HiRes (page #{isa_page == 0x2000 ? 1 : 2})", isa_bitmap, cycles_run)

          ir_bitmap = decode_hires_ir(ir_sim, ir_page)
          print_hires_screen("IR HiRes (page #{ir_page == 0x2000 ? 1 : 2})", ir_bitmap, cycles_run)
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

    # Unique PCs visited
    isa_unique = isa_pc_sequence.uniq
    ir_unique = ir_pc_sequence.uniq
    common_pcs = isa_unique & ir_unique

    puts "\nUnique PCs visited:"
    puts "  ISA: #{isa_unique.length} unique PCs"
    puts "  IR:  #{ir_unique.length} unique PCs"
    puts "  Common: #{common_pcs.length} PCs visited by both"

    # Page-level analysis (more tolerant of timing)
    isa_unique_pages = isa_page_sequence.uniq
    ir_unique_pages = ir_page_sequence.uniq
    common_pages = isa_unique_pages & ir_unique_pages

    puts "\nUnique PC pages (256-byte granularity):"
    puts "  ISA: #{isa_unique_pages.length} unique pages"
    puts "  IR:  #{ir_unique_pages.length} unique pages"
    puts "  Common: #{common_pages.length} pages visited by both"

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

    isa_region_counts = isa_regions.tally.sort_by { |_, v| -v }
    ir_region_counts = ir_regions.tally.sort_by { |_, v| -v }

    puts "\nRegion distribution:"
    puts "  ISA: #{isa_region_counts.map { |r, c| "#{r}=#{c}" }.join(', ')}"
    puts "  IR:  #{ir_region_counts.map { |r, c| "#{r}=#{c}" }.join(', ')}"

    # Check for stuck behavior
    ir_stuck_in_one_region = ir_region_counts.first[1] > (ir_regions.length * 0.9)
    if ir_stuck_in_one_region
      puts "\n  ⚠️  IR appears stuck in #{ir_region_counts.first[0]} region"
    end

    # Text memory comparison
    isa_text = text_checksum_isa(isa_bus)
    ir_text = text_checksum_ir(ir_sim)
    text_match = isa_text == ir_text

    puts "\nFinal text memory:"
    puts "  ISA checksum: #{isa_text.to_s(16)}"
    puts "  IR checksum:  #{ir_text.to_s(16)}"
    puts "  Match: #{text_match ? 'YES' : 'NO'}"

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
  end
end
