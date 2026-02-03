# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Require the headless runners with explicit paths
require_relative '../../../examples/mos6502/utilities/runners/headless_runner'
require_relative '../../../examples/apple2/utilities/runners/headless_runner'
require_relative '../../../examples/gameboy/utilities/runners/headless_runner'

RSpec.describe 'Headless Runners', :slow do
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

  describe 'MOS6502::HeadlessRunner' do

    describe 'ISA mode (default)' do
      it 'creates ISA mode runner by default with demo' do
        runner = MOS6502::HeadlessRunner.with_demo(mode: :isa)
        expect(runner.mode).to eq(:isa)
        # simulator_type is :ruby when native extensions not available
        expect(runner.simulator_type).to be_a(Symbol)
      end

      it 'loads demo program into memory' do
        runner = MOS6502::HeadlessRunner.with_demo(mode: :isa)
        program_area = runner.memory_sample[:program_area]
        expect(program_area.any? { |b| b != 0 }).to be true
      end

      it 'loads binary file' do
        with_temp_program do |path|
          runner = MOS6502::HeadlessRunner.new(mode: :isa)
          runner.load_program(path, base_addr: 0x0800)
          runner.setup_reset_vector(0x0800)
          program_area = runner.memory_sample[:program_area]
          expect(program_area[0]).to eq(0xA9)  # LDA
          expect(program_area[1]).to eq(0x42)  # #$42
          expect(program_area[2]).to eq(0x00)  # BRK
        end
      end
    end

    describe 'HDL mode' do
      before(:each) do
        skip 'HDL mode for mos6502 requires native IR extension' unless ir_interpreter_available?
      end

      it 'creates HDL mode runner with interpret backend' do
        runner = MOS6502::HeadlessRunner.new(mode: :hdl, sim: :interpret)
        expect(runner.mode).to eq(:hdl)
        expect(runner.backend).to eq(:interpret)
      end

      it 'creates HDL mode runner with jit backend' do
        skip 'IR JIT not available' unless ir_jit_available?
        runner = MOS6502::HeadlessRunner.new(mode: :hdl, sim: :jit)
        expect(runner.mode).to eq(:hdl)
        expect(runner.backend).to eq(:jit)
      end

      it 'creates HDL mode runner with compile backend' do
        skip 'IR Compiler not available' unless ir_compiler_available?
        runner = MOS6502::HeadlessRunner.new(mode: :hdl, sim: :compile)
        expect(runner.mode).to eq(:hdl)
        expect(runner.backend).to eq(:compile)
      end
    end

    describe 'runner interface' do
      it 'returns all required fields' do
        runner = MOS6502::HeadlessRunner.with_demo(mode: :isa)
        expect(runner.mode).to be_a(Symbol)
        expect(runner.simulator_type).to be_a(Symbol)
        expect([true, false]).to include(runner.native?)
        expect(runner.cpu_state).to be_a(Hash)
        expect(runner.memory_sample).to be_a(Hash)
      end

      it 'returns cpu_state with all register fields' do
        runner = MOS6502::HeadlessRunner.with_demo(mode: :isa)
        cpu_state = runner.cpu_state
        expect(cpu_state).to have_key(:pc)
        expect(cpu_state).to have_key(:a)
        expect(cpu_state).to have_key(:x)
        expect(cpu_state).to have_key(:y)
        expect(cpu_state).to have_key(:sp)
        expect(cpu_state).to have_key(:p)
        expect(cpu_state).to have_key(:cycles)
        expect(cpu_state).to have_key(:halted)
      end

      it 'returns memory_sample with all memory regions' do
        runner = MOS6502::HeadlessRunner.with_demo(mode: :isa)
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
        expect { MOS6502::HeadlessRunner.new(mode: :invalid) }.to raise_error(RuntimeError)
      end
    end
  end

  describe 'RHDL::Apple2::HeadlessRunner' do
    describe 'HDL mode with Ruby backend (default)' do
      it 'creates HDL mode runner by default with demo' do
        runner = RHDL::Apple2::HeadlessRunner.with_demo
        expect(runner.mode).to eq(:hdl)
        expect(runner.backend).to eq(:ruby)
        expect(runner.simulator_type).to eq(:hdl_ruby)
      end

      it 'sets native flag to false for Ruby backend' do
        runner = RHDL::Apple2::HeadlessRunner.with_demo
        expect(runner.native?).to be false
      end

      it 'loads demo program into memory' do
        runner = RHDL::Apple2::HeadlessRunner.with_demo
        program_area = runner.memory_sample[:program_area]
        expect(program_area.any? { |b| b != 0 }).to be true
      end

      it 'loads binary file' do
        with_temp_program do |path|
          runner = RHDL::Apple2::HeadlessRunner.new
          runner.load_program(path, base_addr: 0x0800)
          runner.setup_reset_vector(0x0800)
          program_area = runner.memory_sample[:program_area]
          expect(program_area[0]).to eq(0xA9)  # LDA
          expect(program_area[1]).to eq(0x42)  # #$42
          expect(program_area[2]).to eq(0x00)  # BRK
        end
      end
    end

    describe 'HDL mode with IR interpret backend' do
      before(:each) do
        skip 'IR Interpreter requires native extension' unless ir_interpreter_available?
      end

      it 'creates HDL mode runner with interpret backend' do
        runner = RHDL::Apple2::HeadlessRunner.new(sim: :interpret)
        expect(runner.mode).to eq(:hdl)
        expect(runner.backend).to eq(:interpret)
      end
    end

    describe 'HDL mode with IR jit backend' do
      before(:each) do
        skip 'IR JIT requires native extension' unless ir_jit_available?
      end

      it 'creates HDL mode runner with jit backend' do
        runner = RHDL::Apple2::HeadlessRunner.new(sim: :jit)
        expect(runner.mode).to eq(:hdl)
        expect(runner.backend).to eq(:jit)
      end
    end

    describe 'HDL mode with IR compile backend' do
      before(:each) do
        skip 'IR Compiler requires native extension' unless ir_compiler_available?
      end

      it 'creates HDL mode runner with compile backend' do
        runner = RHDL::Apple2::HeadlessRunner.new(sim: :compile)
        expect(runner.mode).to eq(:hdl)
        expect(runner.backend).to eq(:compile)
      end

      it 'respects sub-cycles option' do
        runner = RHDL::Apple2::HeadlessRunner.new(sim: :compile, sub_cycles: 7)
        expect(runner.mode).to eq(:hdl)
        expect(runner.backend).to eq(:compile)
      end
    end

    describe 'Netlist mode' do
      before(:each) do
        skip 'Netlist requires native extension' unless ir_interpreter_available?
      end

      it 'creates netlist mode runner' do
        runner = RHDL::Apple2::HeadlessRunner.new(mode: :netlist, sim: :interpret)
        expect(runner.mode).to eq(:netlist)
      end
    end

    describe 'runner interface' do
      it 'returns all required fields' do
        runner = RHDL::Apple2::HeadlessRunner.with_demo
        expect(runner.mode).to eq(:hdl)
        expect(runner.simulator_type).to eq(:hdl_ruby)
        expect(runner.native?).to be false
        expect(runner.backend).to eq(:ruby)
        expect(runner.cpu_state).to be_a(Hash)
        expect(runner.memory_sample).to be_a(Hash)
      end

      it 'returns cpu_state with all register fields' do
        runner = RHDL::Apple2::HeadlessRunner.with_demo
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
        runner = RHDL::Apple2::HeadlessRunner.with_demo
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
  end

  describe 'RHDL::GameBoy::HeadlessRunner' do
    describe 'HDL mode with Ruby backend (default)' do
      it 'creates HDL mode runner by default' do
        runner = RHDL::GameBoy::HeadlessRunner.new
        expect(runner.mode).to eq(:hdl)
        expect(runner.backend).to eq(:ruby)
        expect(runner.simulator_type).to eq(:hdl_ruby)
      end

      it 'sets native flag to false for Ruby backend' do
        runner = RHDL::GameBoy::HeadlessRunner.new
        expect(runner.native?).to be false
      end

      it 'loads test ROM' do
        runner = RHDL::GameBoy::HeadlessRunner.with_test_rom
        expect(runner.rom_size).to be > 0
      end
    end

    describe 'HDL mode with IR interpret backend' do
      before(:each) do
        skip 'IR Interpreter requires native extension' unless ir_interpreter_available?
      end

      it 'creates HDL mode runner with interpret backend' do
        runner = RHDL::GameBoy::HeadlessRunner.new(sim: :interpret)
        expect(runner.mode).to eq(:hdl)
        expect(runner.backend).to eq(:interpret)
      end
    end

    describe 'HDL mode with IR jit backend' do
      before(:each) do
        skip 'IR JIT requires native extension' unless ir_jit_available?
      end

      it 'creates HDL mode runner with jit backend' do
        runner = RHDL::GameBoy::HeadlessRunner.new(sim: :jit)
        expect(runner.mode).to eq(:hdl)
        expect(runner.backend).to eq(:jit)
      end
    end

    describe 'HDL mode with IR compile backend' do
      before(:each) do
        skip 'IR Compiler requires native extension' unless ir_compiler_available?
      end

      it 'creates HDL mode runner with compile backend' do
        runner = RHDL::GameBoy::HeadlessRunner.new(sim: :compile)
        expect(runner.mode).to eq(:hdl)
        expect(runner.backend).to eq(:compile)
      end
    end

    describe 'runner interface' do
      it 'returns all required fields' do
        runner = RHDL::GameBoy::HeadlessRunner.with_test_rom
        expect(runner.mode).to eq(:hdl)
        expect(runner.simulator_type).to eq(:hdl_ruby)
        expect(runner.native?).to be false
        expect(runner.backend).to eq(:ruby)
        expect(runner.cpu_state).to be_a(Hash)
      end

      it 'returns cpu_state with all register fields' do
        runner = RHDL::GameBoy::HeadlessRunner.with_test_rom
        cpu_state = runner.cpu_state
        expect(cpu_state).to have_key(:pc)
        expect(cpu_state).to have_key(:a)
        expect(cpu_state).to have_key(:f)
        expect(cpu_state).to have_key(:sp)
        expect(cpu_state).to have_key(:cycles)
        expect(cpu_state).to have_key(:halted)
        expect(cpu_state).to have_key(:simulator_type)
      end
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
end
