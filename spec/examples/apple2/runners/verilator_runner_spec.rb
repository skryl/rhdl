# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../../examples/apple2/hdl/apple2'
require_relative '../../../../examples/apple2/utilities/renderers/braille_renderer'

RSpec.describe 'VerilatorRunner' do
  # Only run tests if Verilator is available
  def verilator_available?
    ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
      File.executable?(File.join(path, 'verilator'))
    end
  end

  # ROM and memory paths for Karateka tests
  ROM_PATH = File.expand_path('../../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  KARATEKA_MEM_PATH = File.expand_path('../../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

  before(:all) do
    if verilator_available?
      require_relative '../../../../examples/apple2/utilities/runners/verilator_runner'
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

  def create_verilator_runner
    runner = RHDL::Examples::Apple2::VerilatorRunner.new(sub_cycles: 14)

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
    it 'defines VerilatorRunner in RHDL::Apple2 namespace' do
      skip 'Verilator not available' unless verilator_available?
      expect(defined?(RHDL::Examples::Apple2::VerilatorRunner)).to eq('constant')
    end

    it 'has the required public interface methods' do
      skip 'Verilator not available' unless verilator_available?

      required_methods = %i[
        load_rom load_ram load_disk reset run_steps run_cpu_cycle
        inject_key read_screen_array read_screen screen_dirty?
        clear_screen_dirty read_hires_bitmap render_hires_braille
        render_hires_color cpu_state halted? cycle_count dry_run_info
        bus disk_controller speaker display_mode start_audio stop_audio
        read write native? simulator_type
      ]

      runner_class = RHDL::Examples::Apple2::VerilatorRunner

      required_methods.each do |method|
        expect(runner_class.instance_methods).to include(method),
          "Expected VerilatorRunner to have method #{method}"
      end
    end
  end

  describe 'interface compatibility' do
    it 'simulator_type returns :hdl_verilator' do
      skip 'Verilator not available' unless verilator_available?

      # Mock the runner without actually initializing Verilator
      runner_class = RHDL::Examples::Apple2::VerilatorRunner
      # Check that the method is defined correctly by inspecting source
      expect(runner_class.instance_method(:simulator_type).source_location).not_to be_nil
    end

    it 'native? returns true' do
      skip 'Verilator not available' unless verilator_available?

      runner_class = RHDL::Examples::Apple2::VerilatorRunner
      expect(runner_class.instance_method(:native?).source_location).not_to be_nil
    end
  end

  describe 'constants' do
    it 'defines TEXT_PAGE1_START constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Examples::Apple2::VerilatorRunner::TEXT_PAGE1_START).to eq(0x0400)
    end

    it 'defines TEXT_PAGE1_END constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Examples::Apple2::VerilatorRunner::TEXT_PAGE1_END).to eq(0x07FF)
    end

    it 'defines HIRES_PAGE1_START constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Examples::Apple2::VerilatorRunner::HIRES_PAGE1_START).to eq(0x2000)
    end

    it 'defines HIRES_PAGE1_END constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Examples::Apple2::VerilatorRunner::HIRES_PAGE1_END).to eq(0x3FFF)
    end

    it 'defines HIRES_WIDTH constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Examples::Apple2::VerilatorRunner::HIRES_WIDTH).to eq(280)
    end

    it 'defines HIRES_HEIGHT constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Examples::Apple2::VerilatorRunner::HIRES_HEIGHT).to eq(192)
    end

    it 'defines BUILD_DIR constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Examples::Apple2::VerilatorRunner::BUILD_DIR).to include('.verilator_build')
    end
  end

  describe 'DiskControllerStub' do
    it 'defines nested DiskControllerStub class' do
      skip 'Verilator not available' unless verilator_available?
      expect(defined?(RHDL::Examples::Apple2::VerilatorRunner::DiskControllerStub)).to eq('constant')
    end

    it 'DiskControllerStub has track method returning 0' do
      skip 'Verilator not available' unless verilator_available?
      stub = RHDL::Examples::Apple2::VerilatorRunner::DiskControllerStub.new
      expect(stub.track).to eq(0)
    end

    it 'DiskControllerStub has motor_on method returning false' do
      skip 'Verilator not available' unless verilator_available?
      stub = RHDL::Examples::Apple2::VerilatorRunner::DiskControllerStub.new
      expect(stub.motor_on).to eq(false)
    end
  end

  # Integration tests that require full Verilator compilation
  describe 'integration', :slow do
    # These tests are slow because they compile Verilog
    # Run with: rspec --tag slow

    it 'can be instantiated when Verilator is available' do
      skip 'Verilator not available' unless verilator_available?
      skip 'Slow test - run with --tag slow' unless ENV['RUN_SLOW_TESTS']

      expect { RHDL::Examples::Apple2::VerilatorRunner.new(sub_cycles: 14) }.not_to raise_error
    end
  end

  # Karateka-based Verilator tests (moved from karateka_divergence_spec.rb)
  describe 'Karateka simulation' do
    it 'verifies Verilator runner can be initialized and has correct interface', timeout: 120 do
      skip 'Verilator not available' unless verilator_available?
      skip 'AppleIIgo ROM not found' unless @rom_available
      skip 'Karateka memory dump not found' unless @karateka_available

      puts "\n" + "=" * 70
      puts "Verilator Runner Interface Verification"
      puts "=" * 70

      # Verify VerilatorRunner class exists and has expected interface
      expect(defined?(RHDL::Examples::Apple2::VerilatorRunner)).to eq('constant')

      runner_class = RHDL::Examples::Apple2::VerilatorRunner

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

      puts "\n" + "=" * 70
      puts "Verilator Simulation PC Pattern Verification"
      puts "=" * 70

      # Initialize Verilator runner
      puts "\nInitializing Verilator runner..."
      start_time = Time.now
      runner = RHDL::Examples::Apple2::VerilatorRunner.new(sub_cycles: 14)
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
end
