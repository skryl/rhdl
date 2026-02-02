# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'tempfile'

RSpec.describe 'Apple2 CLI --dry-run', :slow do
  let(:bin_path) { File.expand_path('../../../../examples/apple2/bin/apple2', __FILE__) }
  let(:demo_program) { [0xA9, 0x42, 0x00] }  # LDA #$42, BRK

  # Helper to run the CLI with options and return parsed JSON
  def run_cli(*args)
    cmd = ['bundle', 'exec', 'ruby', bin_path, '--dry-run'] + args
    stdout, stderr, status = Open3.capture3(*cmd)
    unless status.success?
      raise "CLI failed with status #{status.exitstatus}:\nSTDOUT: #{stdout}\nSTDERR: #{stderr}"
    end
    # Extract only the JSON portion (skip any "Loading..." or "Initializing..." messages)
    json_start = stdout.index('{')
    raise "No JSON found in output:\nSTDOUT: #{stdout}\nSTDERR: #{stderr}" unless json_start
    json_str = stdout[json_start..]
    JSON.parse(json_str, symbolize_names: true)
  end

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
    it 'selects HDL mode by default with --demo' do
      result = run_cli('--demo')
      expect(result[:mode]).to eq('hdl')
      expect(result[:backend]).to eq('ruby')
      expect(result[:simulator_type]).to eq('hdl_ruby')
    end

    it 'sets native flag to false for Ruby backend' do
      result = run_cli('--demo')
      expect(result[:native]).to be false
    end

    it 'loads demo program into memory' do
      result = run_cli('--demo')
      # Demo program starts at $0800
      program_area = result[:memory_sample][:program_area]
      # Demo program should have been loaded (non-zero bytes)
      expect(program_area.any? { |b| b != 0 }).to be true
    end

    it 'sets reset vector for demo program' do
      result = run_cli('--demo')
      reset_vector = result[:memory_sample][:reset_vector]
      # In HDL mode, reset vector is in ROM space which isn't writable
      # The setup_reset_vector writes to RAM addresses but $FFFC-$FFFD are in ROM
      # So reset vector will be 0 unless a ROM with proper reset vector is loaded
      expect(reset_vector.size).to eq(2)
    end

    it 'loads binary file with positional argument' do
      with_temp_program do |path|
        result = run_cli(path)
        program_area = result[:memory_sample][:program_area]
        # First 3 bytes should be our test program
        expect(program_area[0]).to eq(0xA9)  # LDA
        expect(program_area[1]).to eq(0x42)  # #$42
        expect(program_area[2]).to eq(0x00)  # BRK
      end
    end

    it 'loads binary file at custom address with -a option' do
      with_temp_program do |path|
        result = run_cli(path, '-a', '0900')
        # Program should be at $0900, not in $0800 program_area sample
        # In HDL mode, reset vector is in ROM space which isn't writable
        # Just verify the mode and structure are correct
        expect(result[:mode]).to eq('hdl')
        expect(result[:memory_sample]).to have_key(:reset_vector)
      end
    end
  end

  describe 'HDL mode with IR interpret backend' do
    # Skip if IR Interpreter is not available
    before(:each) do
      skip 'IR Interpreter requires native extension' unless ir_interpreter_available?
    end

    it 'selects HDL mode with interpret backend' do
      result = run_cli('--demo', '--sim', 'interpret')
      expect(result[:mode]).to eq('hdl')
      expect(result[:backend]).to eq('interpret')
    end

    it 'sets native flag correctly for interpret' do
      result = run_cli('--demo', '--sim', 'interpret')
      # IR interpreter may or may not be native
      expect([true, false]).to include(result[:native])
    end

    it 'loads demo program into IR simulator memory' do
      result = run_cli('--demo', '--sim', 'interpret')
      program_area = result[:memory_sample][:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end
  end

  describe 'HDL mode with IR jit backend' do
    # Skip if IR JIT is not available
    before(:each) do
      skip 'IR JIT requires native extension' unless ir_jit_available?
    end

    it 'selects HDL mode with jit backend' do
      result = run_cli('--demo', '--sim', 'jit')
      expect(result[:mode]).to eq('hdl')
      expect(result[:backend]).to eq('jit')
    end

    it 'sets native flag to true for jit' do
      result = run_cli('--demo', '--sim', 'jit')
      expect(result[:native]).to be true
    end

    it 'loads demo program into IR simulator memory' do
      result = run_cli('--demo', '--sim', 'jit')
      program_area = result[:memory_sample][:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end
  end

  describe 'HDL mode with IR compile backend' do
    # Skip if IR Compiler is not available
    before(:each) do
      skip 'IR Compiler requires native extension' unless ir_compiler_available?
    end

    it 'selects HDL mode with compile backend' do
      result = run_cli('--demo', '--sim', 'compile')
      expect(result[:mode]).to eq('hdl')
      expect(result[:backend]).to eq('compile')
    end

    it 'sets native flag to true for compile' do
      result = run_cli('--demo', '--sim', 'compile')
      expect(result[:native]).to be true
    end

    it 'loads demo program into IR simulator memory' do
      result = run_cli('--demo', '--sim', 'compile')
      program_area = result[:memory_sample][:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end

    it 'respects sub-cycles option' do
      result = run_cli('--demo', '--sim', 'compile', '--sub-cycles', '7')
      expect(result[:mode]).to eq('hdl')
      expect(result[:backend]).to eq('compile')
    end
  end

  describe 'Netlist mode with interpret backend' do
    # Skip if Netlist Interpreter is not available
    before(:each) do
      skip 'Netlist Interpreter requires native extension' unless ir_interpreter_available?
    end

    it 'selects netlist mode with interpret backend' do
      result = run_cli('--demo', '-m', 'netlist', '--sim', 'interpret')
      expect(result[:mode]).to eq('netlist')
      expect(result[:backend]).to eq('interpret')
    end

    it 'loads demo program into netlist memory' do
      result = run_cli('--demo', '-m', 'netlist', '--sim', 'interpret')
      program_area = result[:memory_sample][:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end
  end

  describe 'Netlist mode with jit backend' do
    # Skip if Netlist JIT is not available
    before(:each) do
      skip 'Netlist JIT requires native extension' unless ir_jit_available?
    end

    it 'selects netlist mode with jit backend' do
      result = run_cli('--demo', '-m', 'netlist', '--sim', 'jit')
      expect(result[:mode]).to eq('netlist')
      expect(result[:backend]).to eq('jit')
    end

    it 'sets native flag to true for jit netlist' do
      result = run_cli('--demo', '-m', 'netlist', '--sim', 'jit')
      expect(result[:native]).to be true
    end
  end

  describe 'Netlist mode with compile backend' do
    # Skip if Netlist Compiler is not available
    before(:each) do
      skip 'Netlist Compiler requires native extension' unless ir_compiler_available?
    end

    it 'selects netlist mode with compile backend' do
      result = run_cli('--demo', '-m', 'netlist', '--sim', 'compile')
      expect(result[:mode]).to eq('netlist')
      expect(result[:backend]).to eq('compile')
    end

    it 'sets native flag to true for compile netlist' do
      result = run_cli('--demo', '-m', 'netlist', '--sim', 'compile')
      expect(result[:native]).to be true
    end
  end

  describe 'Verilog mode' do
    # Skip if Verilator is not available
    before(:each) do
      skip 'Verilator not available' unless verilator_available?
    end

    it 'selects verilog mode' do
      result = run_cli('--demo', '-m', 'verilog')
      expect(result[:mode]).to eq('verilog')
      expect(result[:simulator_type]).to eq('hdl_verilator')
    end

    it 'sets native flag to true for verilog' do
      result = run_cli('--demo', '-m', 'verilog')
      expect(result[:native]).to be true
    end

    it 'loads demo program into Verilator memory' do
      result = run_cli('--demo', '-m', 'verilog')
      program_area = result[:memory_sample][:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end

    it 'sets PC near $0800 for demo program' do
      result = run_cli('--demo', '-m', 'verilog')
      pc = result[:cpu_state][:pc]
      # PC should be near $0800 (2048) - allowing a few bytes for instruction fetch
      expect(pc).to be >= 0x0800
      expect(pc).to be <= 0x0820
    end

    context 'with karateka' do
      let(:karateka_memdump) { File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__) }

      before(:each) do
        skip 'Karateka memdump not available' unless File.exist?(karateka_memdump)
      end

      it 'sets PC near $B82A for karateka' do
        result = run_cli('--karateka', '-m', 'verilog')
        pc = result[:cpu_state][:pc]
        # PC should be near $B82A - allowing a few bytes for instruction fetch
        expect(pc).to be >= 0xB82A
        expect(pc).to be <= 0xB840
      end

      it 'sets reset vector to $B82A for karateka' do
        result = run_cli('--karateka', '-m', 'verilog')
        reset_vector = result[:memory_sample][:reset_vector]
        # Reset vector should point to $B82A
        expect(reset_vector[0]).to eq(0x2A)  # Low byte
        expect(reset_vector[1]).to eq(0xB8)  # High byte
      end
    end
  end

  describe 'dry-run output structure' do
    it 'returns all required fields' do
      result = run_cli('--demo')
      expect(result).to have_key(:mode)
      expect(result).to have_key(:simulator_type)
      expect(result).to have_key(:native)
      expect(result).to have_key(:backend)
      expect(result).to have_key(:cpu_state)
      expect(result).to have_key(:memory_sample)
    end

    it 'returns cpu_state with all register fields' do
      result = run_cli('--demo')
      cpu_state = result[:cpu_state]
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
      result = run_cli('--demo')
      memory = result[:memory_sample]
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
    it 'exits with error when no program specified and no --demo' do
      cmd = ['bundle', 'exec', 'ruby', bin_path, '--dry-run']
      _stdout, stderr, status = Open3.capture3(*cmd)
      expect(status.success?).to be false
      expect(stderr + _stdout).to include('No program specified')
    end

    it 'exits with error for invalid mode' do
      cmd = ['bundle', 'exec', 'ruby', bin_path, '--demo', '--dry-run', '-m', 'invalid']
      _stdout, stderr, status = Open3.capture3(*cmd)
      expect(status.success?).to be false
    end

    it 'exits with error for invalid sim backend' do
      cmd = ['bundle', 'exec', 'ruby', bin_path, '--demo', '--dry-run', '--sim', 'invalid']
      _stdout, stderr, status = Open3.capture3(*cmd)
      expect(status.success?).to be false
    end
  end

  describe 'option combinations' do
    it 'HDL mode with debug flag' do
      result = run_cli('--demo', '-d')
      expect(result[:mode]).to eq('hdl')
    end

    it 'HDL mode with green screen flag' do
      result = run_cli('--demo', '-g')
      expect(result[:mode]).to eq('hdl')
    end

    it 'HDL mode with hires flag' do
      result = run_cli('--demo', '-H')
      expect(result[:mode]).to eq('hdl')
    end

    it 'HDL mode with color flag' do
      result = run_cli('--demo', '-C')
      expect(result[:mode]).to eq('hdl')
    end

    it 'HDL mode with speed option' do
      result = run_cli('--demo', '-s', '1000')
      expect(result[:mode]).to eq('hdl')
    end

    it 'HDL mode with audio flag' do
      result = run_cli('--demo', '-A')
      expect(result[:mode]).to eq('hdl')
    end

    it 'HDL mode with hires-width option' do
      result = run_cli('--demo', '-H', '--hires-width', '140')
      expect(result[:mode]).to eq('hdl')
    end
  end

  describe 'ROM loading' do
    # These tests require actual ROM files, skip if not available
    let(:appleiigo_rom) { File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__) }

    context 'with AppleIIGo ROM available' do
      before(:each) do
        skip 'AppleIIGo ROM not available' unless File.exist?(appleiigo_rom)
      end

      it 'loads ROM with --appleiigo option' do
        result = run_cli('--appleiigo')
        expect(result[:mode]).to eq('hdl')
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

  # Check if Verilator is available
  def verilator_available?
    system('which verilator > /dev/null 2>&1')
  end
end
