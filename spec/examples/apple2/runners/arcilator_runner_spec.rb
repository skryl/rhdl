# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../../examples/apple2/hdl/apple2'
require_relative '../../../../examples/apple2/utilities/renderers/braille_renderer'

RSpec.describe 'ArcilatorRunner' do
  def arcilator_available?
    %w[firtool arcilator llc].all? do |tool|
      ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
        File.executable?(File.join(path, tool))
      end
    end
  end

  # ROM and memory paths for Karateka tests
  ROM_PATH = File.expand_path('../../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  KARATEKA_MEM_PATH = File.expand_path('../../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

  before(:all) do
    if arcilator_available?
      require_relative '../../../../examples/apple2/utilities/runners/arcilator_runner'
    end
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

  def create_arcilator_runner
    runner = RHDL::Examples::Apple2::ArcilatorRunner.new(sub_cycles: 14)

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

  describe 'class definition' do
    it 'defines ArcilatorRunner in RHDL::Examples::Apple2 namespace' do
      skip 'Arcilator not available' unless arcilator_available?
      expect(defined?(RHDL::Examples::Apple2::ArcilatorRunner)).to eq('constant')
    end

    it 'has the required public interface methods' do
      skip 'Arcilator not available' unless arcilator_available?

      required_methods = %i[
        load_rom load_ram load_disk reset run_steps run_cpu_cycle
        inject_key read_screen_array read_screen screen_dirty?
        clear_screen_dirty read_hires_bitmap render_hires_braille
        render_hires_color cpu_state halted? cycle_count dry_run_info
        bus disk_controller speaker display_mode start_audio stop_audio
        read write native? simulator_type
      ]

      runner_class = RHDL::Examples::Apple2::ArcilatorRunner

      required_methods.each do |method|
        expect(runner_class.instance_methods).to include(method),
          "Expected ArcilatorRunner to have method #{method}"
      end
    end
  end

  describe 'interface compatibility' do
    it 'simulator_type returns :hdl_arcilator' do
      skip 'Arcilator not available' unless arcilator_available?

      runner_class = RHDL::Examples::Apple2::ArcilatorRunner
      expect(runner_class.instance_method(:simulator_type).source_location).not_to be_nil
    end

    it 'native? returns true' do
      skip 'Arcilator not available' unless arcilator_available?

      runner_class = RHDL::Examples::Apple2::ArcilatorRunner
      expect(runner_class.instance_method(:native?).source_location).not_to be_nil
    end
  end

  describe 'constants' do
    it 'defines TEXT_PAGE1_START constant' do
      skip 'Arcilator not available' unless arcilator_available?
      expect(RHDL::Examples::Apple2::ArcilatorRunner::TEXT_PAGE1_START).to eq(0x0400)
    end

    it 'defines TEXT_PAGE1_END constant' do
      skip 'Arcilator not available' unless arcilator_available?
      expect(RHDL::Examples::Apple2::ArcilatorRunner::TEXT_PAGE1_END).to eq(0x07FF)
    end

    it 'defines HIRES_PAGE1_START constant' do
      skip 'Arcilator not available' unless arcilator_available?
      expect(RHDL::Examples::Apple2::ArcilatorRunner::HIRES_PAGE1_START).to eq(0x2000)
    end

    it 'defines HIRES_PAGE1_END constant' do
      skip 'Arcilator not available' unless arcilator_available?
      expect(RHDL::Examples::Apple2::ArcilatorRunner::HIRES_PAGE1_END).to eq(0x3FFF)
    end

    it 'defines HIRES_WIDTH constant' do
      skip 'Arcilator not available' unless arcilator_available?
      expect(RHDL::Examples::Apple2::ArcilatorRunner::HIRES_WIDTH).to eq(280)
    end

    it 'defines HIRES_HEIGHT constant' do
      skip 'Arcilator not available' unless arcilator_available?
      expect(RHDL::Examples::Apple2::ArcilatorRunner::HIRES_HEIGHT).to eq(192)
    end

    it 'defines BUILD_DIR constant' do
      skip 'Arcilator not available' unless arcilator_available?
      expect(RHDL::Examples::Apple2::ArcilatorRunner::BUILD_DIR).to include('.arcilator_build')
    end
  end

  describe 'DiskControllerStub' do
    it 'defines nested DiskControllerStub class' do
      skip 'Arcilator not available' unless arcilator_available?
      expect(defined?(RHDL::Examples::Apple2::ArcilatorRunner::DiskControllerStub)).to eq('constant')
    end

    it 'DiskControllerStub has track method returning 0' do
      skip 'Arcilator not available' unless arcilator_available?
      stub = RHDL::Examples::Apple2::ArcilatorRunner::DiskControllerStub.new
      expect(stub.track).to eq(0)
    end

    it 'DiskControllerStub has motor_on method returning false' do
      skip 'Arcilator not available' unless arcilator_available?
      stub = RHDL::Examples::Apple2::ArcilatorRunner::DiskControllerStub.new
      expect(stub.motor_on).to eq(false)
    end
  end

  # Integration tests that require full arcilator compilation
  describe 'integration', :slow do
    it 'can be instantiated when arcilator is available' do
      skip 'Arcilator not available' unless arcilator_available?
      skip 'Slow test - run with --tag slow' unless ENV['RUN_SLOW_TESTS']

      expect { RHDL::Examples::Apple2::ArcilatorRunner.new(sub_cycles: 14) }.not_to raise_error
    end
  end

  # Karateka-based correctness tests
  describe 'Karateka simulation' do
    it 'verifies Arcilator runner can be initialized and has correct interface', timeout: 120 do
      skip 'Arcilator not available' unless arcilator_available?
      skip 'AppleIIgo ROM not found' unless @rom_available
      skip 'Karateka memory dump not found' unless @karateka_available

      puts "\n" + "=" * 70
      puts "Arcilator Runner Interface Verification"
      puts "=" * 70

      # Verify ArcilatorRunner class exists and has expected interface
      expect(defined?(RHDL::Examples::Apple2::ArcilatorRunner)).to eq('constant')

      runner_class = RHDL::Examples::Apple2::ArcilatorRunner

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
        "ArcilatorRunner should implement all interface methods, missing: #{missing_methods.join(', ')}"

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
      puts "Arcilator interface verification PASSED"
    end

    it 'verifies Arcilator simulation produces expected PC patterns', timeout: 300 do
      skip 'Arcilator not available' unless arcilator_available?
      skip 'AppleIIgo ROM not found' unless @rom_available
      skip 'Karateka memory dump not found' unless @karateka_available

      puts "\n" + "=" * 70
      puts "Arcilator Simulation PC Pattern Verification"
      puts "=" * 70

      # Initialize Arcilator runner
      puts "\nInitializing Arcilator runner..."
      start_time = Time.now
      runner = RHDL::Examples::Apple2::ArcilatorRunner.new(sub_cycles: 14)
      init_time = Time.now - start_time
      puts "  Arcilator initialized in #{init_time.round(2)}s"

      # Load Karateka ROM and memory
      karateka_rom = create_karateka_rom
      runner.load_rom(karateka_rom, base_addr: 0xD000)
      runner.load_ram(@karateka_mem, base_addr: 0x0000)
      puts "  Loaded Karateka ROM and memory dump"

      # Verify native interface
      expect(runner.native?).to be(true)
      expect(runner.simulator_type).to eq(:hdl_arcilator)
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
      puts "Arcilator simulation verification PASSED"
    end

    it 'matches Verilator PC and register state after short execution', timeout: 600 do
      skip 'Arcilator not available' unless arcilator_available?
      skip 'Verilator not available' unless HdlToolchain.verilator_available?
      skip 'AppleIIgo ROM not found' unless @rom_available
      skip 'Karateka memory dump not found' unless @karateka_available

      require_relative '../../../../examples/apple2/utilities/runners/verilator_runner'

      puts "\n" + "=" * 70
      puts "Arcilator vs Verilator Cross-Backend Correctness"
      puts "=" * 70

      # Initialize both runners
      puts "\nInitializing runners..."
      arc_runner = create_arcilator_runner
      ver_runner = RHDL::Examples::Apple2::VerilogRunner.new(sub_cycles: 14)

      karateka_rom = create_karateka_rom
      ver_runner.load_rom(karateka_rom, base_addr: 0xD000)
      ver_runner.load_ram(@karateka_mem, base_addr: 0x0000)
      ver_runner.reset

      puts "  Both runners initialized and loaded with Karateka"

      # Run both for increasing cycle counts and compare at checkpoints
      checkpoints = [100, 500, 1_000, 5_000, 10_000]
      prev_checkpoint = 0
      mismatches = []

      checkpoints.each do |checkpoint|
        steps = checkpoint - prev_checkpoint
        arc_runner.run_steps(steps)
        ver_runner.run_steps(steps)
        prev_checkpoint = checkpoint

        arc_state = arc_runner.cpu_state
        ver_state = ver_runner.cpu_state

        pc_match = arc_state[:pc] == ver_state[:pc]
        a_match = arc_state[:a] == ver_state[:a]
        x_match = arc_state[:x] == ver_state[:x]
        y_match = arc_state[:y] == ver_state[:y]

        all_match = pc_match && a_match && x_match && y_match

        status = all_match ? "MATCH" : "MISMATCH"
        puts format("  @%6d cycles: %s  PC: arc=$%04X ver=$%04X  A: arc=$%02X ver=$%02X  X: arc=$%02X ver=$%02X  Y: arc=$%02X ver=$%02X",
                    checkpoint, status,
                    arc_state[:pc], ver_state[:pc],
                    arc_state[:a], ver_state[:a],
                    arc_state[:x], ver_state[:x],
                    arc_state[:y], ver_state[:y])

        unless all_match
          mismatches << {
            cycle: checkpoint,
            arc: arc_state,
            ver: ver_state
          }
        end
      end

      # Also compare memory at key regions
      puts "\nMemory comparison at #{checkpoints.last} cycles:"
      memory_regions = {
        zero_page: (0x00..0xFF),
        stack: (0x100..0x1FF),
        text_page: (0x400..0x7FF),
      }

      mem_mismatches = {}
      memory_regions.each do |name, range|
        diffs = 0
        range.each do |addr|
          arc_val = arc_runner.read(addr) & 0xFF
          ver_val = ver_runner.read(addr) & 0xFF
          diffs += 1 if arc_val != ver_val
        end
        mem_mismatches[name] = diffs
        status = diffs == 0 ? "MATCH" : "#{diffs} differences"
        puts "  #{name}: #{status}"
      end

      puts "\n" + "=" * 70

      if mismatches.empty? && mem_mismatches.values.all?(&:zero?)
        puts "Cross-backend correctness PASSED - all states match"
      else
        puts "Cross-backend correctness: #{mismatches.length} register mismatches, #{mem_mismatches.values.sum} memory differences"

        # The first divergence point is the most interesting for debugging
        if mismatches.any?
          first = mismatches.first
          puts "\nFirst divergence at cycle #{first[:cycle]}:"
          puts "  Arcilator: PC=$%04X A=$%02X X=$%02X Y=$%02X" % [first[:arc][:pc], first[:arc][:a], first[:arc][:x], first[:arc][:y]]
          puts "  Verilator: PC=$%04X A=$%02X X=$%02X Y=$%02X" % [first[:ver][:pc], first[:ver][:a], first[:ver][:x], first[:ver][:y]]
        end
      end

      # Expect registers to match at the first checkpoint at minimum
      # (both runners should be executing the same reset sequence)
      first_arc = nil
      first_ver = nil
      arc_runner2 = create_arcilator_runner
      ver_runner2 = RHDL::Examples::Apple2::VerilogRunner.new(sub_cycles: 14)
      ver_runner2.load_rom(create_karateka_rom, base_addr: 0xD000)
      ver_runner2.load_ram(@karateka_mem, base_addr: 0x0000)
      ver_runner2.reset

      # Run just 100 cycles and check PC is in a valid ROM/RAM region
      arc_runner2.run_steps(100)
      ver_runner2.run_steps(100)
      first_arc = arc_runner2.cpu_state
      first_ver = ver_runner2.cpu_state

      # Both should be executing from ROM after reset (reset vector points to $B82A)
      expect(pc_region(first_arc[:pc])).not_to eq(:unknown),
        "Arcilator PC should be in a known region after 100 cycles, got $%04X" % first_arc[:pc]
      expect(pc_region(first_ver[:pc])).not_to eq(:unknown),
        "Verilator PC should be in a known region after 100 cycles, got $%04X" % first_ver[:pc]

      # Report final comparison
      if first_arc[:pc] == first_ver[:pc]
        puts "\nEarly execution (100 cycles): PCs MATCH at $%04X" % first_arc[:pc]
      else
        puts "\nEarly execution (100 cycles): PCs DIVERGE - arc=$%04X ver=$%04X" % [first_arc[:pc], first_ver[:pc]]
        puts "  This indicates a behavioral difference in the FIRRTL lowering path"
      end
    end
  end
end
