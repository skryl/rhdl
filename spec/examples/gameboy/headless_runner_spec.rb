# frozen_string_literal: true

require 'spec_helper'

# Add the utilities path to load the headless runner
$LOAD_PATH.unshift(File.expand_path('../../../../examples/gameboy/utilities/runners', __FILE__))
require 'headless_runner'

RSpec.describe RHDL::Examples::GameBoy::HeadlessRunner, :slow do
  describe 'Ruby mode (default)' do
    it 'creates Ruby mode runner with Ruby backend by default' do
      runner = described_class.new
      expect(runner.mode).to eq(:ruby)
      expect(runner.backend).to eq(:ruby)
      expect(runner.simulator_type).to eq(:hdl_ruby)
    end

    it 'sets native flag to false for Ruby backend' do
      runner = described_class.new
      expect(runner.native?).to be false
    end

    it 'loads test ROM' do
      runner = described_class.with_test_rom
      expect(runner.rom_size).to be > 0
    end

    it 'can reset the system' do
      runner = described_class.with_test_rom
      expect { runner.reset }.not_to raise_error
    end
  end

  describe 'IR mode with interpret backend' do
    before(:each) do
      skip 'IR Interpreter requires native extension' unless ir_interpreter_available?
    end

    it 'creates IR mode runner with interpret backend' do
      runner = described_class.new(mode: :ir, sim: :interpret)
      expect(runner.mode).to eq(:ir)
      expect(runner.backend).to eq(:interpret)
    end

    it 'loads test ROM into IR simulator' do
      runner = described_class.with_test_rom(mode: :ir, sim: :interpret)
      expect(runner.rom_size).to be > 0
    end
  end

  describe 'IR mode with jit backend' do
    before(:each) do
      skip 'IR JIT requires native extension' unless ir_jit_available?
    end

    it 'creates IR mode runner with jit backend' do
      runner = described_class.new(mode: :ir, sim: :jit)
      expect(runner.mode).to eq(:ir)
      expect(runner.backend).to eq(:jit)
    end

    it 'sets native flag to true for jit' do
      runner = described_class.new(mode: :ir, sim: :jit)
      expect(runner.native?).to be true
    end

    it 'loads test ROM into IR simulator' do
      runner = described_class.with_test_rom(mode: :ir, sim: :jit)
      expect(runner.rom_size).to be > 0
    end
  end

  describe 'IR mode with compile backend' do
    before(:each) do
      skip 'IR Compiler requires native extension' unless ir_compiler_available?
    end

    it 'creates IR mode runner with compile backend' do
      runner = described_class.new(mode: :ir, sim: :compile)
      expect(runner.mode).to eq(:ir)
      expect(runner.backend).to eq(:compile)
    end

    it 'sets native flag to true for compile' do
      runner = described_class.new(mode: :ir, sim: :compile)
      expect(runner.native?).to be true
    end

    it 'loads test ROM into IR simulator' do
      runner = described_class.with_test_rom(mode: :ir, sim: :compile)
      expect(runner.rom_size).to be > 0
    end
  end

  describe 'Verilog mode' do
    before(:each) do
      skip 'Verilator not available' unless verilator_available?
    end

    it 'creates verilog mode runner' do
      runner = described_class.new(mode: :verilog)
      expect(runner.mode).to eq(:verilog)
      expect(runner.simulator_type).to eq(:hdl_verilator)
    end

    it 'sets native flag to true for verilog' do
      runner = described_class.new(mode: :verilog)
      expect(runner.native?).to be true
    end

    it 'loads test ROM into Verilator' do
      runner = described_class.with_test_rom(mode: :verilog)
      expect(runner.rom_size).to be > 0
    end
  end

  describe 'runner interface' do
    it 'returns all cpu_state fields' do
      runner = described_class.with_test_rom
      cpu_state = runner.cpu_state
      expect(cpu_state).to have_key(:pc)
      expect(cpu_state).to have_key(:a)
      expect(cpu_state).to have_key(:f)
      expect(cpu_state).to have_key(:sp)
      expect(cpu_state).to have_key(:cycles)
      expect(cpu_state).to have_key(:halted)
      expect(cpu_state).to have_key(:simulator_type)
    end

    it 'provides cycle_count method' do
      runner = described_class.with_test_rom
      expect(runner.cycle_count).to be_a(Integer)
      expect(runner.cycle_count).to eq(0)
    end

    it 'provides halted? method' do
      runner = described_class.with_test_rom
      expect([true, false]).to include(runner.halted?)
    end

    it 'provides run_steps method' do
      runner = described_class.with_test_rom
      runner.reset
      expect { runner.run_steps(10) }.not_to raise_error
    end
  end

  describe 'test ROM generation' do
    it 'creates a valid test ROM' do
      rom = described_class.create_test_rom
      expect(rom.size).to be >= 0x150
      # Entry point should be NOP + JP
      expect(rom[0x100]).to eq(0x00)  # NOP
      expect(rom[0x101]).to eq(0xC3)  # JP
    end

    it 'includes Nintendo logo' do
      rom = described_class.create_test_rom
      # First byte of Nintendo logo
      expect(rom[0x104]).to eq(0xCE)
    end

    it 'includes valid header checksum' do
      rom = described_class.create_test_rom
      checksum = 0
      (0x134..0x14C).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
      expect(rom[0x14D]).to eq(checksum)
    end
  end

  private

  # Check if IR interpreter is available
  def ir_interpreter_available?
    require 'rhdl/codegen'
    RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
  rescue LoadError, NameError
    false
  end

  # Check if IR JIT is available
  def ir_jit_available?
    require 'rhdl/codegen'
    RHDL::Codegen::IR::IR_JIT_AVAILABLE
  rescue LoadError, NameError
    false
  end

  # Check if IR Compiler is available
  def ir_compiler_available?
    require 'rhdl/codegen'
    RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
  rescue LoadError, NameError
    false
  end

  # Check if Verilator is available
  def verilator_available?
    system('which verilator > /dev/null 2>&1')
  end
end
