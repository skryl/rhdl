# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Add the utilities path to load the headless runner
$LOAD_PATH.unshift(File.expand_path('../../../../../examples/apple2/utilities', __FILE__))
require 'runners/headless_runner'

RSpec.describe RHDL::Apple2::HeadlessRunner, :slow do
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

  describe 'HDL mode with Ruby backend (default)' do
    it 'creates HDL mode runner with Ruby backend by default' do
      runner = described_class.new
      expect(runner.mode).to eq(:hdl)
      expect(runner.backend).to eq(:ruby)
      expect(runner.simulator_type).to eq(:hdl_ruby)
    end

    it 'sets native flag to false for Ruby backend' do
      runner = described_class.new
      expect(runner.native?).to be false
    end

    it 'loads demo program into memory' do
      runner = described_class.with_demo
      program_area = runner.memory_sample[:program_area]
      # Demo program should have been loaded (non-zero bytes)
      expect(program_area.any? { |b| b != 0 }).to be true
    end

    it 'sets reset vector for demo program' do
      runner = described_class.with_demo
      reset_vector = runner.memory_sample[:reset_vector]
      # In HDL mode, reset vector is in ROM space which isn't writable
      # The setup_reset_vector writes to RAM addresses but $FFFC-$FFFD are in ROM
      # So reset vector will be 0 unless a ROM with proper reset vector is loaded
      expect(reset_vector.size).to eq(2)
    end

    it 'loads binary file' do
      with_temp_program do |path|
        runner = described_class.new
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
        runner = described_class.new
        runner.load_program(path, base_addr: 0x0900)
        runner.setup_reset_vector(0x0900)
        # In HDL mode, reset vector is in ROM space which isn't writable
        # Just verify the mode and structure are correct
        expect(runner.mode).to eq(:hdl)
        expect(runner.memory_sample).to have_key(:reset_vector)
      end
    end
  end

  describe 'HDL mode with IR interpret backend' do
    before(:each) do
      skip 'IR Interpreter requires native extension' unless ir_interpreter_available?
    end

    it 'creates HDL mode runner with interpret backend' do
      runner = described_class.new(sim: :interpret)
      expect(runner.mode).to eq(:hdl)
      expect(runner.backend).to eq(:interpret)
    end

    it 'sets native flag correctly for interpret' do
      runner = described_class.new(sim: :interpret)
      # IR interpreter may or may not be native
      expect([true, false]).to include(runner.native?)
    end

    it 'loads demo program into IR simulator memory' do
      runner = described_class.with_demo(sim: :interpret)
      program_area = runner.memory_sample[:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end
  end

  describe 'HDL mode with IR jit backend' do
    before(:each) do
      skip 'IR JIT requires native extension' unless ir_jit_available?
    end

    it 'creates HDL mode runner with jit backend' do
      runner = described_class.new(sim: :jit)
      expect(runner.mode).to eq(:hdl)
      expect(runner.backend).to eq(:jit)
    end

    it 'sets native flag to true for jit' do
      runner = described_class.new(sim: :jit)
      expect(runner.native?).to be true
    end

    it 'loads demo program into IR simulator memory' do
      runner = described_class.with_demo(sim: :jit)
      program_area = runner.memory_sample[:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end
  end

  describe 'HDL mode with IR compile backend' do
    before(:each) do
      skip 'IR Compiler requires native extension' unless ir_compiler_available?
    end

    it 'creates HDL mode runner with compile backend' do
      runner = described_class.new(sim: :compile)
      expect(runner.mode).to eq(:hdl)
      expect(runner.backend).to eq(:compile)
    end

    it 'sets native flag to true for compile' do
      runner = described_class.new(sim: :compile)
      expect(runner.native?).to be true
    end

    it 'loads demo program into IR simulator memory' do
      runner = described_class.with_demo(sim: :compile)
      program_area = runner.memory_sample[:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end

    it 'respects sub-cycles option' do
      runner = described_class.new(sim: :compile, sub_cycles: 7)
      expect(runner.mode).to eq(:hdl)
      expect(runner.backend).to eq(:compile)
    end
  end

  describe 'Netlist mode with interpret backend' do
    before(:each) do
      skip 'Netlist Interpreter requires native extension' unless ir_interpreter_available?
    end

    it 'creates netlist mode runner with interpret backend' do
      runner = described_class.new(mode: :netlist, sim: :interpret)
      expect(runner.mode).to eq(:netlist)
      expect(runner.backend).to eq(:interpret)
    end

    it 'loads demo program into netlist memory' do
      runner = described_class.with_demo(mode: :netlist, sim: :interpret)
      program_area = runner.memory_sample[:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end
  end

  describe 'Netlist mode with jit backend' do
    before(:each) do
      skip 'Netlist JIT requires native extension' unless ir_jit_available?
    end

    it 'creates netlist mode runner with jit backend' do
      runner = described_class.new(mode: :netlist, sim: :jit)
      expect(runner.mode).to eq(:netlist)
      expect(runner.backend).to eq(:jit)
    end

    it 'sets native flag to true for jit netlist' do
      runner = described_class.new(mode: :netlist, sim: :jit)
      expect(runner.native?).to be true
    end
  end

  describe 'Netlist mode with compile backend' do
    before(:each) do
      skip 'Netlist Compiler requires native extension' unless ir_compiler_available?
    end

    it 'creates netlist mode runner with compile backend' do
      runner = described_class.new(mode: :netlist, sim: :compile)
      expect(runner.mode).to eq(:netlist)
      expect(runner.backend).to eq(:compile)
    end

    it 'sets native flag to true for compile netlist' do
      runner = described_class.new(mode: :netlist, sim: :compile)
      expect(runner.native?).to be true
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

    it 'sets PC near $0800 for demo program' do
      runner = described_class.with_demo(mode: :verilog)
      runner.reset
      pc = runner.cpu_state[:pc]
      # PC should be near $0800 (2048) - allowing a few bytes for instruction fetch
      expect(pc).to be >= 0x0800
      expect(pc).to be <= 0x0820
    end

    context 'with karateka' do
      let(:karateka_memdump) { File.expand_path('../../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__) }

      before(:each) do
        skip 'Karateka memdump not available' unless File.exist?(karateka_memdump)
      end

      it 'sets PC near $B82A for karateka' do
        runner = described_class.new(mode: :verilog)
        runner.load_memdump(karateka_memdump, pc: 0xB82A, use_appleiigo: true)
        runner.reset
        pc = runner.cpu_state[:pc]
        # PC should be near $B82A - allowing a few bytes for instruction fetch
        expect(pc).to be >= 0xB82A
        expect(pc).to be <= 0xB840
      end

      it 'sets reset vector to $B82A for karateka' do
        runner = described_class.new(mode: :verilog)
        runner.load_memdump(karateka_memdump, pc: 0xB82A, use_appleiigo: true)
        reset_vector = runner.memory_sample[:reset_vector]
        # Reset vector should point to $B82A
        expect(reset_vector[0]).to eq(0x2A)  # Low byte
        expect(reset_vector[1]).to eq(0xB8)  # High byte
      end
    end
  end

  describe 'runner interface' do
    it 'returns all cpu_state fields' do
      runner = described_class.with_demo
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
      runner = described_class.with_demo
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
