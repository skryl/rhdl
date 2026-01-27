# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'tempfile'

RSpec.describe 'MOS6502 CLI --dry-run', :slow do
  let(:bin_path) { File.expand_path('../../../../examples/mos6502/bin/mos6502', __FILE__) }
  let(:demo_program) { [0xA9, 0x42, 0x00] }  # LDA #$42, BRK

  # Helper to run the CLI with options and return parsed JSON
  def run_cli(*args)
    cmd = ['bundle', 'exec', 'ruby', bin_path, '--dry-run'] + args
    stdout, stderr, status = Open3.capture3(*cmd)
    unless status.success?
      raise "CLI failed with status #{status.exitstatus}:\nSTDOUT: #{stdout}\nSTDERR: #{stderr}"
    end
    # Extract only the JSON portion (skip any "Loading..." messages)
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

  describe 'ISA mode (default)' do
    it 'selects ISA mode by default with --demo' do
      result = run_cli('--demo')
      expect(result[:mode]).to eq('isa')
      expect(result[:backend]).to be_nil
    end

    it 'returns native or ruby simulator_type based on availability' do
      result = run_cli('--demo')
      expect(['native', 'ruby']).to include(result[:simulator_type])
    end

    it 'sets native flag correctly' do
      result = run_cli('--demo')
      # native flag should match simulator_type
      if result[:simulator_type] == 'native'
        expect(result[:native]).to be true
      else
        expect(result[:native]).to be false
      end
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
      # Reset vector should point to $0800
      expect(reset_vector[0]).to eq(0x00)  # Low byte
      expect(reset_vector[1]).to eq(0x08)  # High byte
    end

    it 'loads binary file with -b option' do
      with_temp_program do |path|
        result = run_cli('-b', path)
        program_area = result[:memory_sample][:program_area]
        # First 3 bytes should be our test program
        expect(program_area[0]).to eq(0xA9)  # LDA
        expect(program_area[1]).to eq(0x42)  # #$42
        expect(program_area[2]).to eq(0x00)  # BRK
      end
    end

    it 'loads binary file at custom address with -a option' do
      with_temp_program do |path|
        result = run_cli('-b', path, '-a', '0900')
        # Program should be at $0900, not in $0800 program_area sample
        # The program_area sample is $0800-$08FF, so won't show our program
        # But we can verify reset vector points to $0900
        reset_vector = result[:memory_sample][:reset_vector]
        expect(reset_vector[0]).to eq(0x00)  # Low byte
        expect(reset_vector[1]).to eq(0x09)  # High byte
      end
    end

    it 'sets custom entry point with -e option' do
      with_temp_program do |path|
        result = run_cli('-b', path, '-e', '0810')
        # Reset vector should point to custom entry
        reset_vector = result[:memory_sample][:reset_vector]
        expect(reset_vector[0]).to eq(0x10)  # Low byte
        expect(reset_vector[1]).to eq(0x08)  # High byte
      end
    end
  end

  describe 'HDL mode with interpret backend' do
    # Skip if IR interpreter is not available
    before(:each) do
      skip 'IR Interpreter not available' unless ir_interpreter_available?
    end

    it 'selects HDL mode with interpret backend' do
      result = run_cli('--demo', '-m', 'hdl', '--sim', 'interpret')
      expect(result[:mode]).to eq('hdl')
      expect(result[:backend]).to eq('interpret')
      expect(result[:simulator_type]).to eq('ir_interpret')
    end

    it 'sets native flag to false for interpret' do
      result = run_cli('--demo', '-m', 'hdl', '--sim', 'interpret')
      expect(result[:native]).to be false
    end

    it 'loads demo program into IR simulator memory' do
      result = run_cli('--demo', '-m', 'hdl', '--sim', 'interpret')
      program_area = result[:memory_sample][:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end
  end

  describe 'HDL mode with jit backend' do
    # Skip if IR JIT is not available
    before(:each) do
      skip 'IR JIT not available' unless ir_jit_available?
    end

    it 'selects HDL mode with jit backend' do
      result = run_cli('--demo', '-m', 'hdl', '--sim', 'jit')
      expect(result[:mode]).to eq('hdl')
      expect(result[:backend]).to eq('jit')
      expect(result[:simulator_type]).to eq('ir_jit')
    end

    it 'sets native flag to true for jit' do
      result = run_cli('--demo', '-m', 'hdl', '--sim', 'jit')
      expect(result[:native]).to be true
    end

    it 'loads demo program into IR simulator memory' do
      result = run_cli('--demo', '-m', 'hdl', '--sim', 'jit')
      program_area = result[:memory_sample][:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end
  end

  describe 'HDL mode with compile backend' do
    # Skip if IR Compiler is not available
    before(:each) do
      skip 'IR Compiler not available' unless ir_compiler_available?
    end

    it 'selects HDL mode with compile backend' do
      result = run_cli('--demo', '-m', 'hdl', '--sim', 'compile')
      expect(result[:mode]).to eq('hdl')
      expect(result[:backend]).to eq('compile')
      expect(result[:simulator_type]).to eq('ir_compile')
    end

    it 'sets native flag to true for compile' do
      result = run_cli('--demo', '-m', 'hdl', '--sim', 'compile')
      expect(result[:native]).to be true
    end

    it 'loads demo program into IR simulator memory' do
      result = run_cli('--demo', '-m', 'hdl', '--sim', 'compile')
      program_area = result[:memory_sample][:program_area]
      expect(program_area.any? { |b| b != 0 }).to be true
    end
  end

  describe 'HDL mode defaults' do
    # HDL mode defaults to jit backend
    before(:each) do
      skip 'IR JIT not available' unless ir_jit_available?
    end

    it 'defaults to jit backend when -m hdl is used without --sim' do
      result = run_cli('--demo', '-m', 'hdl')
      expect(result[:mode]).to eq('hdl')
      expect(result[:backend]).to eq('jit')
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

    it 'exits with error for missing binary file' do
      cmd = ['bundle', 'exec', 'ruby', bin_path, '--dry-run', '-b', '/nonexistent/file.bin']
      _stdout, stderr, status = Open3.capture3(*cmd)
      expect(status.success?).to be false
      expect(stderr + _stdout).to include('not found')
    end
  end

  describe 'option combinations' do
    it 'ISA mode with debug flag' do
      result = run_cli('--demo', '-d')
      expect(result[:mode]).to eq('isa')
    end

    it 'ISA mode with green screen flag' do
      result = run_cli('--demo', '-g')
      expect(result[:mode]).to eq('isa')
    end

    it 'ISA mode with hires flag' do
      result = run_cli('--demo', '-H')
      expect(result[:mode]).to eq('isa')
    end

    it 'ISA mode with speed option' do
      result = run_cli('--demo', '-s', '1000')
      expect(result[:mode]).to eq('isa')
    end

    it 'ISA mode with no-audio flag' do
      result = run_cli('--demo', '--no-audio')
      expect(result[:mode]).to eq('isa')
    end
  end

  describe 'ROM loading' do
    # These tests require actual ROM files, skip if not available
    let(:appleiigo_rom) { File.expand_path('../../../../examples/mos6502/software/roms/appleiigo.rom', __FILE__) }

    context 'with AppleIIGo ROM available', if: -> { File.exist?(File.expand_path('../../../../examples/mos6502/software/roms/appleiigo.rom', __FILE__)) } do
      it 'loads ROM with --appleiigo option' do
        skip 'AppleIIGo ROM not available' unless File.exist?(appleiigo_rom)
        result = run_cli('--appleiigo')
        expect(result[:mode]).to eq('isa')
        # ROM should be loaded at $D000
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
