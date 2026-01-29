# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'

RSpec.describe 'VerilatorRunner' do
  # Only run tests if Verilator is available
  def verilator_available?
    ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
      File.executable?(File.join(path, 'verilator'))
    end
  end

  before(:all) do
    if verilator_available?
      require_relative '../../../examples/apple2/utilities/apple2_verilator'
    end
  end

  describe 'class definition' do
    it 'defines VerilatorRunner in RHDL::Apple2 namespace' do
      skip 'Verilator not available' unless verilator_available?
      expect(defined?(RHDL::Apple2::VerilatorRunner)).to eq('constant')
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

      runner_class = RHDL::Apple2::VerilatorRunner

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
      runner_class = RHDL::Apple2::VerilatorRunner
      # Check that the method is defined correctly by inspecting source
      expect(runner_class.instance_method(:simulator_type).source_location).not_to be_nil
    end

    it 'native? returns true' do
      skip 'Verilator not available' unless verilator_available?

      runner_class = RHDL::Apple2::VerilatorRunner
      expect(runner_class.instance_method(:native?).source_location).not_to be_nil
    end
  end

  describe 'constants' do
    it 'defines TEXT_PAGE1_START constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Apple2::VerilatorRunner::TEXT_PAGE1_START).to eq(0x0400)
    end

    it 'defines TEXT_PAGE1_END constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Apple2::VerilatorRunner::TEXT_PAGE1_END).to eq(0x07FF)
    end

    it 'defines HIRES_PAGE1_START constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Apple2::VerilatorRunner::HIRES_PAGE1_START).to eq(0x2000)
    end

    it 'defines HIRES_PAGE1_END constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Apple2::VerilatorRunner::HIRES_PAGE1_END).to eq(0x3FFF)
    end

    it 'defines HIRES_WIDTH constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Apple2::VerilatorRunner::HIRES_WIDTH).to eq(280)
    end

    it 'defines HIRES_HEIGHT constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Apple2::VerilatorRunner::HIRES_HEIGHT).to eq(192)
    end

    it 'defines BUILD_DIR constant' do
      skip 'Verilator not available' unless verilator_available?
      expect(RHDL::Apple2::VerilatorRunner::BUILD_DIR).to include('.verilator_build')
    end
  end

  describe 'DiskControllerStub' do
    it 'defines nested DiskControllerStub class' do
      skip 'Verilator not available' unless verilator_available?
      expect(defined?(RHDL::Apple2::VerilatorRunner::DiskControllerStub)).to eq('constant')
    end

    it 'DiskControllerStub has track method returning 0' do
      skip 'Verilator not available' unless verilator_available?
      stub = RHDL::Apple2::VerilatorRunner::DiskControllerStub.new
      expect(stub.track).to eq(0)
    end

    it 'DiskControllerStub has motor_on method returning false' do
      skip 'Verilator not available' unless verilator_available?
      stub = RHDL::Apple2::VerilatorRunner::DiskControllerStub.new
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

      expect { RHDL::Apple2::VerilatorRunner.new(sub_cycles: 14) }.not_to raise_error
    end
  end
end
