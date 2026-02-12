# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Load the headless runner using require_relative
require_relative '../../../../../examples/mos6502/utilities/runners/headless_runner'

RSpec.describe RHDL::Examples::MOS6502::HeadlessRunner, :slow do
  let(:demo_program) { [0xA9, 0x42, 0x00] }  # LDA #$42, BRK

  # Helper to create a temp binary file with test program
  def with_temp_program(bytes = demo_program)
    Tempfile.create(['test_program', '.bin']) do |f|
      f.binmode
      f.write(bytes.pack('C*'))
      f.flush
      yield f.path
    end
  end

  describe 'ISA mode (default)' do
    it 'creates ISA mode runner' do
      runner = described_class.new(mode: :isa)
      expect(runner.mode).to eq(:isa)
      expect([:native, :ruby]).to include(runner.backend)
    end

    it 'returns native or ruby simulator_type based on availability' do
      runner = described_class.new(mode: :isa)
      expect([:native, :ruby]).to include(runner.simulator_type)
    end

    it 'sets native flag correctly' do
      runner = described_class.new(mode: :isa)
      if runner.simulator_type == :native
        expect(runner.native?).to be true
      else
        expect(runner.native?).to be false
      end
    end

    it 'loads demo program into memory' do
      runner = described_class.with_demo(mode: :isa)
      program_area = runner.memory_sample[:program_area]
      # Demo program should have been loaded (non-zero bytes)
      expect(program_area.any? { |b| b != 0 }).to be true
    end

    it 'sets reset vector for demo program' do
      runner = described_class.with_demo(mode: :isa)
      reset_vector = runner.memory_sample[:reset_vector]
      # Reset vector should point to $0800
      expect(reset_vector[0]).to eq(0x00)  # Low byte
      expect(reset_vector[1]).to eq(0x08)  # High byte
    end

    it 'loads binary file' do
      with_temp_program do |path|
        runner = described_class.new(mode: :isa)
        runner.load_program(path, base_addr: 0x0800)
        runner.setup_reset_vector(0x0800)
        program_area = runner.memory_sample[:program_area]
        # First 3 bytes should be our test program
        expect(program_area[0]).to eq(0xA9)  # LDA
        expect(program_area[1]).to eq(0x42)  # #$42
        expect(program_area[2]).to eq(0x00)  # BRK
      end
    end

    it 'loads binary file at custom address' do
      with_temp_program do |path|
        runner = described_class.new(mode: :isa)
        runner.load_program(path, base_addr: 0x0900)
        runner.setup_reset_vector(0x0900)
        # Reset vector should point to $0900
        reset_vector = runner.memory_sample[:reset_vector]
        expect(reset_vector[0]).to eq(0x00)  # Low byte
        expect(reset_vector[1]).to eq(0x09)  # High byte
      end
    end

    it 'sets custom entry point' do
      with_temp_program do |path|
        runner = described_class.new(mode: :isa)
        runner.load_program(path, base_addr: 0x0800)
        runner.setup_reset_vector(0x0810)
        # Reset vector should point to custom entry
        reset_vector = runner.memory_sample[:reset_vector]
        expect(reset_vector[0]).to eq(0x10)  # Low byte
        expect(reset_vector[1]).to eq(0x08)  # High byte
      end
    end

    it 'supports explicit ruby ISA backend' do
      runner = described_class.new(mode: :isa, sim: :ruby)
      expect(runner.backend).to eq(:ruby)
      expect(runner.simulator_type).to eq(:ruby)
      expect(runner.native?).to be false
    end

    it 'requires native extension for explicit native ISA backend' do
      if RHDL::Examples::MOS6502::NATIVE_AVAILABLE
        runner = described_class.new(mode: :isa, sim: :native)
        expect(runner.backend).to eq(:native)
        expect(runner.native?).to be true
      else
        expect { described_class.new(mode: :isa, sim: :native) }
          .to raise_error(RuntimeError, /native extension is unavailable/i)
      end
    end
  end

  describe 'Ruby HDL mode' do
    it 'creates Ruby HDL mode runner' do
      runner = described_class.new(mode: :ruby, sim: :ruby)
      expect(runner.mode).to eq(:ruby)
      expect(runner.backend).to eq(:ruby)
      expect(runner.simulator_type).to eq(:hdl_ruby)
      expect(runner.native?).to be false
    end
  end

  describe 'HDL mode with interpret backend' do
    before(:each) do
      skip 'IR Interpreter not available' unless ir_interpreter_available?
    end

    it 'creates HDL mode runner with interpret backend' do
      runner = described_class.new(mode: :ir, sim: :interpret)
      expect(runner.mode).to eq(:ir)
      expect(runner.backend).to eq(:interpret)
      expect(runner.simulator_type).to eq(:ir_interpret)
    end

    it 'sets native flag to false for interpret' do
      runner = described_class.new(mode: :ir, sim: :interpret)
      expect(runner.native?).to be false
    end

    it 'loads demo program into IR simulator memory' do
      runner = described_class.with_demo(mode: :ir, sim: :interpret)
      program_area = runner.memory_sample[:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end
  end

  describe 'HDL mode with jit backend' do
    before(:each) do
      skip 'IR JIT not available' unless ir_jit_available?
    end

    it 'creates HDL mode runner with jit backend' do
      runner = described_class.new(mode: :ir, sim: :jit)
      expect(runner.mode).to eq(:ir)
      expect(runner.backend).to eq(:jit)
      expect(runner.simulator_type).to eq(:ir_jit)
    end

    it 'sets native flag to true for jit' do
      runner = described_class.new(mode: :ir, sim: :jit)
      expect(runner.native?).to be true
    end

    it 'loads demo program into IR simulator memory' do
      runner = described_class.with_demo(mode: :ir, sim: :jit)
      program_area = runner.memory_sample[:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end
  end

  describe 'HDL mode with compile backend' do
    before(:each) do
      skip 'IR Compiler not available' unless ir_compiler_available?
    end

    it 'creates HDL mode runner with compile backend' do
      runner = described_class.new(mode: :ir, sim: :compile)
      expect(runner.mode).to eq(:ir)
      expect(runner.backend).to eq(:compile)
      expect(runner.simulator_type).to eq(:ir_compile)
    end

    it 'sets native flag to true for compile' do
      runner = described_class.new(mode: :ir, sim: :compile)
      expect(runner.native?).to be true
    end

    it 'loads demo program into IR simulator memory' do
      runner = described_class.with_demo(mode: :ir, sim: :compile)
      program_area = runner.memory_sample[:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
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

    it 'loads demo program into Verilator memory' do
      runner = described_class.with_demo(mode: :verilog)
      program_area = runner.memory_sample[:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end
  end

  describe 'runner interface' do
    it 'returns all cpu_state fields' do
      runner = described_class.with_demo(mode: :isa)
      cpu_state = runner.cpu_state
      expect(cpu_state).to have_key(:pc)
      expect(cpu_state).to have_key(:a)
      expect(cpu_state).to have_key(:x)
      expect(cpu_state).to have_key(:y)
      expect(cpu_state).to have_key(:sp)
      expect(cpu_state).to have_key(:p)
      expect(cpu_state).to have_key(:cycles)
      expect(cpu_state).to have_key(:halted)
      expect(cpu_state).to have_key(:simulator_type)
    end

    it 'returns memory_sample with all memory regions' do
      runner = described_class.with_demo(mode: :isa)
      memory = runner.memory_sample
      expect(memory).to have_key(:zero_page)
      expect(memory).to have_key(:stack)
      expect(memory).to have_key(:text_page)
      expect(memory).to have_key(:program_area)
      expect(memory).to have_key(:reset_vector)

      # Verify sizes
      expect(memory[:zero_page].size).to eq(256)
      expect(memory[:stack].size).to eq(256)
      expect(memory[:text_page].size).to eq(1024)
      expect(memory[:program_area].size).to eq(256)
      expect(memory[:reset_vector].size).to eq(2)
    end
  end

  describe 'error handling' do
    it 'raises error for invalid mode' do
      expect { described_class.new(mode: :invalid) }.to raise_error(RuntimeError, /Unknown mode/)
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
