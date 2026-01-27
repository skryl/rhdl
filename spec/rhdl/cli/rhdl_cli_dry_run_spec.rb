# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'tempfile'

RSpec.describe 'RHDL CLI examples --dry-run', :slow do
  let(:rhdl_path) { File.expand_path('../../../../exe/rhdl', __FILE__) }
  let(:demo_program) { [0xA9, 0x42, 0x00] }  # LDA #$42, BRK

  # Helper to run the CLI with options and return parsed JSON
  def run_rhdl(*args)
    cmd = ['bundle', 'exec', 'ruby', rhdl_path] + args
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

  describe 'rhdl examples mos6502' do
    describe 'ISA mode (default)' do
      it 'selects ISA mode by default with --demo' do
        result = run_rhdl('examples', 'mos6502', '--demo', '--dry-run')
        expect(result[:mode]).to eq('isa')
        # simulator_type is "ruby" when native extensions not available
        expect(result[:simulator_type]).to be_a(String)
      end

      it 'loads demo program into memory' do
        result = run_rhdl('examples', 'mos6502', '--demo', '--dry-run')
        program_area = result[:memory_sample][:program_area]
        expect(program_area.any? { |b| b != 0 }).to be true
      end

      it 'loads binary file with positional argument' do
        with_temp_program do |path|
          result = run_rhdl('examples', 'mos6502', '--dry-run', path)
          program_area = result[:memory_sample][:program_area]
          expect(program_area[0]).to eq(0xA9)  # LDA
          expect(program_area[1]).to eq(0x42)  # #$42
          expect(program_area[2]).to eq(0x00)  # BRK
        end
      end
    end

    describe 'HDL mode' do
      # All HDL modes for mos6502 require native IR extension
      before(:each) do
        skip 'HDL mode for mos6502 requires native IR extension'
      end

      it 'selects HDL mode with -m hdl' do
        result = run_rhdl('examples', 'mos6502', '--demo', '-m', 'hdl', '--dry-run')
        expect(result[:mode]).to eq('hdl')
      end

      it 'selects HDL mode with interpret backend' do
        result = run_rhdl('examples', 'mos6502', '--demo', '-m', 'hdl', '--sim', 'interpret', '--dry-run')
        expect(result[:mode]).to eq('hdl')
        expect(result[:backend]).to eq('interpret')
      end

      it 'selects HDL mode with jit backend' do
        result = run_rhdl('examples', 'mos6502', '--demo', '-m', 'hdl', '--sim', 'jit', '--dry-run')
        expect(result[:mode]).to eq('hdl')
        expect(result[:backend]).to eq('jit')
      end

      it 'selects HDL mode with compile backend' do
        result = run_rhdl('examples', 'mos6502', '--demo', '-m', 'hdl', '--sim', 'compile', '--dry-run')
        expect(result[:mode]).to eq('hdl')
        expect(result[:backend]).to eq('compile')
      end
    end

    describe 'Netlist mode' do
      before(:each) do
        skip 'Netlist requires native extension'
      end

      it 'selects netlist mode with -m netlist' do
        result = run_rhdl('examples', 'mos6502', '--demo', '-m', 'netlist', '--dry-run')
        expect(result[:mode]).to eq('netlist')
      end
    end

    describe 'dry-run output structure' do
      it 'returns all required fields' do
        result = run_rhdl('examples', 'mos6502', '--demo', '--dry-run')
        expect(result).to have_key(:mode)
        expect(result).to have_key(:simulator_type)
        expect(result).to have_key(:native)
        expect(result).to have_key(:cpu_state)
        expect(result).to have_key(:memory_sample)
      end

      it 'returns cpu_state with all register fields' do
        result = run_rhdl('examples', 'mos6502', '--demo', '--dry-run')
        cpu_state = result[:cpu_state]
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
        result = run_rhdl('examples', 'mos6502', '--demo', '--dry-run')
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
        cmd = ['bundle', 'exec', 'ruby', rhdl_path, 'examples', 'mos6502', '--dry-run']
        _stdout, stderr, status = Open3.capture3(*cmd)
        expect(status.success?).to be false
        expect(stderr + _stdout).to include('No program specified')
      end

      it 'exits with error for invalid mode' do
        cmd = ['bundle', 'exec', 'ruby', rhdl_path, 'examples', 'mos6502', '--demo', '--dry-run', '-m', 'invalid']
        _stdout, stderr, status = Open3.capture3(*cmd)
        expect(status.success?).to be false
      end

      it 'exits with error for invalid sim backend' do
        cmd = ['bundle', 'exec', 'ruby', rhdl_path, 'examples', 'mos6502', '--demo', '--dry-run', '--sim', 'invalid']
        _stdout, stderr, status = Open3.capture3(*cmd)
        expect(status.success?).to be false
      end
    end

    describe 'option passthrough' do
      it 'passes through debug flag' do
        result = run_rhdl('examples', 'mos6502', '--demo', '-d', '--dry-run')
        expect(result[:mode]).to eq('isa')
      end

      it 'passes through speed option' do
        result = run_rhdl('examples', 'mos6502', '--demo', '-s', '1000', '--dry-run')
        expect(result[:mode]).to eq('isa')
      end

      it 'passes through green flag' do
        result = run_rhdl('examples', 'mos6502', '--demo', '-g', '--dry-run')
        expect(result[:mode]).to eq('isa')
      end

      it 'passes through hires flag' do
        result = run_rhdl('examples', 'mos6502', '--demo', '-H', '--dry-run')
        expect(result[:mode]).to eq('isa')
      end

      it 'passes through hires-width option' do
        result = run_rhdl('examples', 'mos6502', '--demo', '-H', '--hires-width', '140', '--dry-run')
        expect(result[:mode]).to eq('isa')
      end

      it 'passes through address option' do
        with_temp_program do |path|
          result = run_rhdl('examples', 'mos6502', '-a', '0900', '--dry-run', path)
          expect(result[:mode]).to eq('isa')
        end
      end

      it 'passes through entry option' do
        with_temp_program do |path|
          result = run_rhdl('examples', 'mos6502', '-e', '0802', '--dry-run', path)
          expect(result[:mode]).to eq('isa')
        end
      end

      it 'passes through init-hires flag' do
        result = run_rhdl('examples', 'mos6502', '--demo', '--init-hires', '--dry-run')
        expect(result[:mode]).to eq('isa')
      end

      it 'passes through no-audio flag' do
        result = run_rhdl('examples', 'mos6502', '--demo', '--no-audio', '--dry-run')
        expect(result[:mode]).to eq('isa')
      end
    end
  end

  describe 'rhdl examples apple2' do
    describe 'HDL mode with Ruby backend (default)' do
      it 'selects HDL mode by default with --demo' do
        result = run_rhdl('examples', 'apple2', '--demo', '--dry-run')
        expect(result[:mode]).to eq('hdl')
        expect(result[:backend]).to eq('ruby')
        expect(result[:simulator_type]).to eq('hdl_ruby')
      end

      it 'sets native flag to false for Ruby backend' do
        result = run_rhdl('examples', 'apple2', '--demo', '--dry-run')
        expect(result[:native]).to be false
      end

      it 'loads demo program into memory' do
        result = run_rhdl('examples', 'apple2', '--demo', '--dry-run')
        program_area = result[:memory_sample][:program_area]
        expect(program_area.any? { |b| b != 0 }).to be true
      end

      it 'loads binary file with positional argument' do
        with_temp_program do |path|
          result = run_rhdl('examples', 'apple2', '--dry-run', path)
          program_area = result[:memory_sample][:program_area]
          expect(program_area[0]).to eq(0xA9)  # LDA
          expect(program_area[1]).to eq(0x42)  # #$42
          expect(program_area[2]).to eq(0x00)  # BRK
        end
      end
    end

    describe 'HDL mode with IR interpret backend' do
      before(:each) do
        skip 'IR Interpreter requires native extension'
      end

      it 'selects HDL mode with interpret backend' do
        result = run_rhdl('examples', 'apple2', '--demo', '--sim', 'interpret', '--dry-run')
        expect(result[:mode]).to eq('hdl')
        expect(result[:backend]).to eq('interpret')
      end
    end

    describe 'HDL mode with IR jit backend' do
      before(:each) do
        skip 'IR JIT requires native extension'
      end

      it 'selects HDL mode with jit backend' do
        result = run_rhdl('examples', 'apple2', '--demo', '--sim', 'jit', '--dry-run')
        expect(result[:mode]).to eq('hdl')
        expect(result[:backend]).to eq('jit')
      end
    end

    describe 'HDL mode with IR compile backend' do
      before(:each) do
        skip 'IR Compiler requires native extension'
      end

      it 'selects HDL mode with compile backend' do
        result = run_rhdl('examples', 'apple2', '--demo', '--sim', 'compile', '--dry-run')
        expect(result[:mode]).to eq('hdl')
        expect(result[:backend]).to eq('compile')
      end

      it 'passes through sub-cycles option' do
        result = run_rhdl('examples', 'apple2', '--demo', '--sim', 'compile', '--sub-cycles', '7', '--dry-run')
        expect(result[:mode]).to eq('hdl')
        expect(result[:backend]).to eq('compile')
      end
    end

    describe 'Netlist mode' do
      before(:each) do
        skip 'Netlist requires native extension'
      end

      it 'selects netlist mode with -m netlist' do
        result = run_rhdl('examples', 'apple2', '--demo', '-m', 'netlist', '--sim', 'interpret', '--dry-run')
        expect(result[:mode]).to eq('netlist')
      end
    end

    describe 'dry-run output structure' do
      it 'returns all required fields' do
        result = run_rhdl('examples', 'apple2', '--demo', '--dry-run')
        expect(result).to have_key(:mode)
        expect(result).to have_key(:simulator_type)
        expect(result).to have_key(:native)
        expect(result).to have_key(:backend)
        expect(result).to have_key(:cpu_state)
        expect(result).to have_key(:memory_sample)
      end

      it 'returns cpu_state with all register fields' do
        result = run_rhdl('examples', 'apple2', '--demo', '--dry-run')
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
        result = run_rhdl('examples', 'apple2', '--demo', '--dry-run')
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
        cmd = ['bundle', 'exec', 'ruby', rhdl_path, 'examples', 'apple2', '--dry-run']
        _stdout, stderr, status = Open3.capture3(*cmd)
        expect(status.success?).to be false
        expect(stderr + _stdout).to include('No program specified')
      end

      it 'exits with error for invalid mode' do
        cmd = ['bundle', 'exec', 'ruby', rhdl_path, 'examples', 'apple2', '--demo', '--dry-run', '-m', 'invalid']
        _stdout, stderr, status = Open3.capture3(*cmd)
        expect(status.success?).to be false
      end

      it 'exits with error for invalid sim backend' do
        cmd = ['bundle', 'exec', 'ruby', rhdl_path, 'examples', 'apple2', '--demo', '--dry-run', '--sim', 'invalid']
        _stdout, stderr, status = Open3.capture3(*cmd)
        expect(status.success?).to be false
      end
    end

    describe 'option passthrough' do
      it 'passes through debug flag' do
        result = run_rhdl('examples', 'apple2', '--demo', '-d', '--dry-run')
        expect(result[:mode]).to eq('hdl')
      end

      it 'passes through speed option' do
        result = run_rhdl('examples', 'apple2', '--demo', '-s', '1000', '--dry-run')
        expect(result[:mode]).to eq('hdl')
      end

      it 'passes through green flag' do
        result = run_rhdl('examples', 'apple2', '--demo', '-g', '--dry-run')
        expect(result[:mode]).to eq('hdl')
      end

      it 'passes through audio flag' do
        result = run_rhdl('examples', 'apple2', '--demo', '-A', '--dry-run')
        expect(result[:mode]).to eq('hdl')
      end

      it 'passes through hires flag' do
        result = run_rhdl('examples', 'apple2', '--demo', '-H', '--dry-run')
        expect(result[:mode]).to eq('hdl')
      end

      it 'passes through color flag' do
        result = run_rhdl('examples', 'apple2', '--demo', '-C', '--dry-run')
        expect(result[:mode]).to eq('hdl')
      end

      it 'passes through hires-width option' do
        result = run_rhdl('examples', 'apple2', '--demo', '-H', '--hires-width', '140', '--dry-run')
        expect(result[:mode]).to eq('hdl')
      end

      it 'passes through address option' do
        with_temp_program do |path|
          result = run_rhdl('examples', 'apple2', '-a', '0900', '--dry-run', path)
          expect(result[:mode]).to eq('hdl')
        end
      end
    end
  end
end
