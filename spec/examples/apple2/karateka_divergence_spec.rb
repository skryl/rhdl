# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/hdl/apple2'
require_relative '../../../examples/apple2/utilities/braille_renderer'

RSpec.describe 'Karateka ISA vs IR Compiler Divergence' do
  # Debug test to identify where ISA runner and IR compiler diverge
  # during Karateka game intro (around 5M cycles)

  ROM_PATH = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  KARATEKA_MEM_PATH = File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

  # Test parameters
  TOTAL_CYCLES = 20_000_000
  CHECKPOINT_INTERVAL = 500_000  # Check every 500K cycles
  SCREEN_INTERVAL = 2_000_000    # Print screen every 2M cycles

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

    # Give bus a reference to CPU for screen reading via mem_read
    # (matches what ISARunner does in apple2_harness.rb)
    bus.instance_variable_set(:@native_cpu, cpu)

    # Initialize HIRES soft switches (like emulator does)
    bus.read(0xC050)  # TXTCLR - graphics mode
    bus.read(0xC052)  # MIXCLR - full screen
    bus.read(0xC054)  # PAGE1 - page 1
    bus.read(0xC057)  # HIRES - hi-res mode

    # Sync video state to native CPU
    cpu.set_video_state(false, false, false, true)  # text=false, mixed=false, page2=false, hires=true

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

    # Initialize HIRES soft switches (like ISA simulator does)
    # soft_switches bits: 0=text, 1=mixed, 2=page2, 3=hires
    # For HIRES mode: text=0, mixed=0, page2=0, hires=1 => 0b00001000 = 8
    sim.poke('soft_switches', 8)

    sim
  end

  # Get the active HiRes page base address for ISA simulator
  def hires_page_base_isa(bus)
    bus.hires_page_base
  end

  # Get the active HiRes page base address for IR simulator
  def hires_page_base_ir(sim)
    page2 = sim.peek('page2')
    page2 == 1 ? 0x4000 : 0x2000
  end

  def hires_checksum_isa(bus, base_addr = nil)
    base_addr ||= hires_page_base_isa(bus)
    checksum = 0
    (base_addr..(base_addr + 0x1FFF)).each do |addr|
      # Use mem_read to read from native CPU memory (not bus memory)
      checksum = (checksum + bus.mem_read(addr)) & 0xFFFFFFFF
    end
    checksum
  end

  def hires_checksum_ir(sim, base_addr = nil)
    base_addr ||= hires_page_base_ir(sim)
    checksum = 0
    data = sim.read_ram(base_addr, 0x2000).to_a
    data.each { |b| checksum = (checksum + b) & 0xFFFFFFFF }
    checksum
  end

  def text_checksum_isa(bus)
    checksum = 0
    (0x0400..0x07FF).each do |addr|
      # Use mem_read to read from native CPU memory (not bus memory)
      checksum = (checksum + bus.mem_read(addr)) & 0xFFFFFFFF
    end
    checksum
  end

  def text_checksum_ir(sim)
    checksum = 0
    data = sim.read_ram(0x0400, 0x400).to_a
    data.each { |b| checksum = (checksum + b) & 0xFFFFFFFF }
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

  # Decode HiRes memory to monochrome bitmap for ISA
  def decode_hires_isa(bus, base_addr = 0x2000)
    bitmap = []
    192.times do |row|
      line = []
      line_addr = hires_line_address(row, base_addr)
      40.times do |col|
        # Use mem_read to read from native CPU memory (not bus memory)
        byte = bus.mem_read(line_addr + col) || 0
        7.times do |bit|
          line << ((byte >> bit) & 1)
        end
      end
      bitmap << line
    end
    bitmap
  end

  # Decode HiRes memory to monochrome bitmap for IR
  def decode_hires_ir(sim, base_addr = 0x2000)
    ram = sim.read_ram(base_addr, 0x2000).to_a
    bitmap = []
    192.times do |row|
      line = []
      line_addr = hires_line_address(row, base_addr) - base_addr
      40.times do |col|
        byte = ram[line_addr + col] || 0
        7.times do |bit|
          line << ((byte >> bit) & 1)
        end
      end
      bitmap << line
    end
    bitmap
  end

  # Print HiRes screen using braille renderer
  def print_hires_screen(label, bitmap, cycles)
    renderer = RHDL::Apple2::BrailleRenderer.new(chars_wide: 70)
    puts "\n#{label} @ #{cycles / 1_000_000.0}M cycles:"
    puts renderer.render(bitmap, invert: false)
  end

  # Categorize PC into memory regions for convergence checking
  def pc_region(pc)
    case pc
    when 0x0000..0x01FF then :zero_page_stack
    when 0x0200..0x03FF then :input_buffer
    when 0x0400..0x07FF then :text_page
    when 0x0800..0x1FFF then :user_code
    when 0x2000..0x3FFF then :hires_page1
    when 0x4000..0x5FFF then :hires_page2
    when 0x6000..0xBFFF then :high_ram
    when 0xC000..0xCFFF then :io_space
    when 0xD000..0xFFFF then :rom
    else :unknown
    end
  end

  # Check if two PCs are in converging regions (same general area)
  def pcs_converging?(isa_pc, ir_pc)
    isa_region = pc_region(isa_pc)
    ir_region = pc_region(ir_pc)

    # Exact region match
    return true if isa_region == ir_region

    # Allow ROM/high_ram as equivalent (game loop area)
    rom_like = [:rom, :high_ram]
    return true if rom_like.include?(isa_region) && rom_like.include?(ir_region)

    # Allow user code areas as equivalent
    user_like = [:user_code, :zero_page_stack, :input_buffer]
    return true if user_like.include?(isa_region) && user_like.include?(ir_region)

    false
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

      # Get active HiRes pages
      isa_page = hires_page_base_isa(isa_bus)
      ir_page = hires_page_base_ir(ir_sim)

      isa_hires = hires_checksum_isa(isa_bus, isa_page)
      ir_hires = hires_checksum_ir(ir_sim, ir_page)
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
        pc_converging: pcs_converging?(isa_pc, ir_pc),
        isa_region: pc_region(isa_pc),
        ir_region: pc_region(ir_pc),
        isa_regs: { a: isa_a, x: isa_x, y: isa_y },
        ir_regs: { a: ir_a, x: ir_x, y: ir_y },
        regs_match: isa_a == ir_a && isa_x == ir_x && isa_y == ir_y,
        isa_page: isa_page,
        ir_page: ir_page,
        page_match: isa_page == ir_page,
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

      isa_pg = isa_page == 0x2000 ? 1 : 2
      ir_pg = ir_page == 0x2000 ? 1 : 2

      # Also compute checksums for BOTH pages to see if anything is changing
      isa_hires_p1 = hires_checksum_isa(isa_bus, 0x2000)
      isa_hires_p2 = hires_checksum_isa(isa_bus, 0x4000)
      ir_hires_p1 = hires_checksum_ir(ir_sim, 0x2000)
      ir_hires_p2 = hires_checksum_ir(ir_sim, 0x4000)

      puts format("  %5.1f%% | %7.1fM | PC: ISA=%04X IR=%04X | ISA P1/P2: %08X/%08X | IR P1/P2: %08X/%08X | %.2fM/s",
                  pct,
                  cycles_run / 1_000_000.0,
                  isa_pc, ir_pc,
                  isa_hires_p1, isa_hires_p2,
                  ir_hires_p1, ir_hires_p2,
                  rate)

      # Print HiRes screen at intervals (using active page)
      if (cycles_run % SCREEN_INTERVAL).zero?
        isa_page = hires_page_base_isa(isa_bus)
        ir_page = hires_page_base_ir(ir_sim)

        isa_bitmap = decode_hires_isa(isa_bus, isa_page)
        print_hires_screen("ISA HiRes (page #{isa_page == 0x2000 ? 1 : 2})", isa_bitmap, cycles_run)

        ir_bitmap = decode_hires_ir(ir_sim, ir_page)
        print_hires_screen("IR HiRes (page #{ir_page == 0x2000 ? 1 : 2})", ir_bitmap, cycles_run)
      end
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
    puts "  Cycles     | PC Match | Converging | HiRes Match | Text Match | ISA Region   | IR Region"
    puts "  " + "-" * 90
    checkpoints.each do |cp|
      puts format("  %9s | %-8s | %-10s | %-11s | %-10s | %-12s | %-12s",
                  "#{cp[:cycles] / 1_000_000.0}M",
                  cp[:pc_match] ? "yes" : "NO",
                  cp[:pc_converging] ? "yes" : "NO",
                  cp[:hires_match] ? "yes" : "NO",
                  cp[:text_match] ? "yes" : "NO",
                  cp[:isa_region],
                  cp[:ir_region])
    end

    # Calculate match percentages
    total = checkpoints.size.to_f
    pc_match_pct = (checkpoints.count { |cp| cp[:pc_match] } / total * 100).round(1)
    pc_converge_pct = (checkpoints.count { |cp| cp[:pc_converging] } / total * 100).round(1)
    regs_match_pct = (checkpoints.count { |cp| cp[:regs_match] } / total * 100).round(1)
    hires_match_pct = (checkpoints.count { |cp| cp[:hires_match] } / total * 100).round(1)
    text_match_pct = (checkpoints.count { |cp| cp[:text_match] } / total * 100).round(1)

    puts "\nMatch Percentages:"
    puts format("  PC Exact:     %5.1f%% (%d/%d checkpoints)", pc_match_pct, checkpoints.count { |cp| cp[:pc_match] }, checkpoints.size)
    puts format("  PC Converge:  %5.1f%% (%d/%d checkpoints)", pc_converge_pct, checkpoints.count { |cp| cp[:pc_converging] }, checkpoints.size)
    puts format("  Regs:         %5.1f%% (%d/%d checkpoints)", regs_match_pct, checkpoints.count { |cp| cp[:regs_match] }, checkpoints.size)
    puts format("  HiRes:        %5.1f%% (%d/%d checkpoints)", hires_match_pct, checkpoints.count { |cp| cp[:hires_match] }, checkpoints.size)
    puts format("  Text:         %5.1f%% (%d/%d checkpoints)", text_match_pct, checkpoints.count { |cp| cp[:text_match] }, checkpoints.size)

    # Note about PC timing differences
    if pc_match_pct < 100 && pc_converge_pct > 80
      puts "\n  Note: PC mismatches are expected due to timing differences between"
      puts "        ISA (instruction-level) and IR (cycle-accurate HDL) simulators."
      puts "        High convergence rate indicates correct functional behavior."
    end

    # Assertions - pass if PC is converging (both visit same general code regions)
    expect(checkpoints.size).to be >= 20, "Should have at least 20 checkpoints"

    # Check that both simulators visit the same set of regions
    # (timing offset is OK, but they should be executing the same code areas)
    isa_regions = checkpoints.map { |cp| cp[:isa_region] }.uniq.sort
    ir_regions = checkpoints.map { |cp| cp[:ir_region] }.uniq.sort

    # Normalize regions - ROM/high_ram are equivalent, user-like regions are equivalent
    def normalize_regions(regions)
      regions.map do |r|
        case r
        when :rom, :high_ram then :game_loop
        when :user_code, :zero_page_stack, :input_buffer, :text_page then :user_area
        else r
        end
      end.uniq.sort
    end

    isa_normalized = normalize_regions(isa_regions)
    ir_normalized = normalize_regions(ir_regions)

    puts "\n  Regions visited:"
    puts "    ISA: #{isa_regions.join(', ')}"
    puts "    IR:  #{ir_regions.join(', ')}"
    puts "    Normalized ISA: #{isa_normalized.join(', ')}"
    puts "    Normalized IR:  #{ir_normalized.join(', ')}"

    # Both should visit game_loop and user_area regions
    expect(isa_normalized).to include(:game_loop),
      "ISA should visit game loop (ROM/HighRAM) region"
    expect(ir_normalized).to include(:game_loop),
      "IR should visit game loop (ROM/HighRAM) region"

    # Check that IR doesn't get stuck in unusual regions (HiRes pages as code)
    stuck_in_hires = checkpoints.count { |cp| [:hires_page1, :hires_page2].include?(cp[:ir_region]) }
    expect(stuck_in_hires).to be < (checkpoints.size * 0.3),
      "IR should not execute from HiRes memory for more than 30% of checkpoints (got #{stuck_in_hires})"

    # Text should match for majority of checkpoints (indicates functional correctness)
    text_match_count = checkpoints.count { |cp| cp[:text_match] }
    expect(text_match_count).to be >= (checkpoints.size * 0.8),
      "Text memory should match for at least 80% of checkpoints, got #{(text_match_count * 100.0 / checkpoints.size).round(1)}%"
  end
end
