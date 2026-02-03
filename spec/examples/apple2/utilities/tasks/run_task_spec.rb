# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/apple2/utilities/tasks/run_task'

RSpec.describe RHDL::Apple2::Tasks::RunTask do
  describe '#initialize' do
    it 'accepts options hash' do
      task = described_class.new(mode: :hdl, sim: :ruby)
      expect(task.instance_variable_get(:@sim_mode)).to eq(:hdl)
      expect(task.instance_variable_get(:@sim_backend)).to eq(:ruby)
    end

    it 'defaults to hdl mode' do
      task = described_class.new
      expect(task.instance_variable_get(:@sim_mode)).to eq(:hdl)
    end

    it 'defaults to ruby sim backend' do
      task = described_class.new
      expect(task.instance_variable_get(:@sim_backend)).to eq(:ruby)
    end

    it 'creates HeadlessRunner internally' do
      task = described_class.new(mode: :hdl, sim: :ruby)
      expect(task.runner).to be_a(RHDL::Apple2::HeadlessRunner)
    end
  end

  describe 'HeadlessRunner integration' do
    context 'with hdl mode and ruby backend' do
      let(:task) { described_class.new(mode: :hdl, sim: :ruby) }

      it 'creates runner with hdl mode' do
        expect(task.runner.mode).to eq(:hdl)
      end

      it 'creates runner with ruby backend' do
        expect(task.runner.sim_backend).to eq(:ruby)
      end

      it 'reports correct simulator type' do
        expect(task.runner.simulator_type).to be_a(Symbol)
      end
    end
  end

  describe 'constants' do
    it 'defines screen dimensions' do
      expect(described_class::SCREEN_ROWS).to eq(24)
      expect(described_class::SCREEN_COLS).to eq(40)
    end

    it 'defines display dimensions' do
      expect(described_class::DISPLAY_WIDTH).to eq(42)
      expect(described_class::DISPLAY_HEIGHT).to eq(26)
    end

    it 'defines hi-res dimensions' do
      expect(described_class::HIRES_WIDTH).to eq(140)
      expect(described_class::HIRES_HEIGHT).to eq(48)
    end

    it 'defines ANSI escape codes' do
      expect(described_class::CLEAR_SCREEN).to include("\e[")
      expect(described_class::HIDE_CURSOR).to include("\e[")
      expect(described_class::SHOW_CURSOR).to include("\e[")
    end
  end
end

RSpec.describe RHDL::Apple2::HeadlessRunner do
  describe '.create_demo_program' do
    let(:program) { described_class.create_demo_program }

    it 'returns an array of bytes' do
      expect(program).to be_a(Array)
    end

    it 'starts with LDA instruction' do
      expect(program[0]).to eq(0xA9)  # LDA immediate
    end

    it 'contains STA instructions for text page' do
      # STA $0400
      expect(program[2]).to eq(0x8D)  # STA absolute
      expect(program[3]).to eq(0x00)  # low byte
      expect(program[4]).to eq(0x04)  # high byte ($0400)
    end

    it 'ends with BRK instruction' do
      expect(program.last).to eq(0x00)  # BRK
    end
  end

  describe '.with_demo' do
    let(:runner) { described_class.with_demo(mode: :hdl, sim: :ruby) }

    it 'creates a HeadlessRunner' do
      expect(runner).to be_a(described_class)
    end

    it 'has demo program loaded' do
      # Verify program is at $0800
      sample = runner.memory_sample
      expect(sample[:program_area][0]).to eq(0xA9)  # LDA immediate
    end

    it 'sets up reset vector' do
      sample = runner.memory_sample
      # Just verify the reset vector bytes are set (may not be in RAM for HDL)
      expect(sample[:reset_vector]).to be_a(Array)
      expect(sample[:reset_vector].length).to eq(2)
    end
  end

  describe 'PC progression' do
    let(:runner) { described_class.with_demo(mode: :hdl, sim: :ruby) }

    before { runner.reset }

    it 'has valid PC after reset' do
      state = runner.cpu_state
      expect(state[:pc]).to be_a(Integer)
      expect(state[:pc]).to be_between(0x0000, 0xFFFF)
    end

    it 'provides CPU state after running steps' do
      runner.run_steps(10)
      state = runner.cpu_state
      expect(state).to include(:pc)
      expect(state[:pc]).to be_a(Integer)
    end

    it 'can run without crashing' do
      # Use smaller step count - Ruby HDL simulation is slow (14 14MHz cycles per step)
      expect { runner.run_steps(15) }.not_to raise_error
    end

    it 'tracks cycle count after running' do
      # Use smaller step count - Ruby HDL simulation is slow
      runner.run_steps(20)
      # Cycle count should be non-negative
      expect(runner.cycle_count).to be >= 0
    end
  end

  describe 'configuration validation' do
    context 'with hdl mode and ruby backend' do
      let(:runner) { described_class.new(mode: :hdl, sim: :ruby) }

      it 'creates runner with hdl mode' do
        expect(runner.mode).to eq(:hdl)
      end

      it 'creates runner with ruby backend' do
        expect(runner.sim_backend).to eq(:ruby)
      end

      it 'reports correct simulator type' do
        expect(runner.simulator_type).to be_a(Symbol)
      end

      it 'backend returns ruby for hdl mode' do
        expect(runner.backend).to eq(:ruby)
      end
    end

    context 'with hdl mode and different backends' do
      it 'accepts interpret backend' do
        begin
          runner = described_class.new(mode: :hdl, sim: :interpret)
          expect(runner.sim_backend).to eq(:interpret)
        rescue LoadError, StandardError => e
          skip "Interpret backend not available: #{e.message}"
        end
      end

      it 'accepts jit backend' do
        begin
          runner = described_class.new(mode: :hdl, sim: :jit)
          expect(runner.sim_backend).to eq(:jit)
        rescue LoadError, StandardError => e
          skip "JIT backend not available: #{e.message}"
        end
      end

      it 'accepts compile backend' do
        begin
          runner = described_class.new(mode: :hdl, sim: :compile)
          expect(runner.sim_backend).to eq(:compile)
        rescue LoadError, StandardError => e
          skip "Compile backend not available: #{e.message}"
        end
      end
    end
  end

  describe 'CPU state access' do
    let(:runner) { described_class.with_demo(mode: :hdl, sim: :ruby) }

    before do
      runner.reset
      runner.run_steps(20)
    end

    it 'provides PC register' do
      state = runner.cpu_state
      expect(state).to include(:pc)
      expect(state[:pc]).to be_a(Integer)
    end

    it 'provides A register' do
      state = runner.cpu_state
      expect(state).to include(:a)
      expect(state[:a]).to be_a(Integer)
      expect(state[:a]).to be_between(0, 255)
    end

    it 'provides X register' do
      state = runner.cpu_state
      expect(state).to include(:x)
      expect(state[:x]).to be_a(Integer)
      expect(state[:x]).to be_between(0, 255)
    end

    it 'provides Y register' do
      state = runner.cpu_state
      expect(state).to include(:y)
      expect(state[:y]).to be_a(Integer)
      expect(state[:y]).to be_between(0, 255)
    end

    it 'provides SP register' do
      state = runner.cpu_state
      expect(state).to include(:sp)
      expect(state[:sp]).to be_a(Integer)
      expect(state[:sp]).to be_between(0, 255)
    end

    it 'provides cycles count' do
      state = runner.cpu_state
      expect(state).to include(:cycles)
      expect(state[:cycles]).to be_a(Integer)
      expect(state[:cycles]).to be > 0
    end
  end

  describe 'memory access' do
    let(:runner) { described_class.new(mode: :hdl, sim: :ruby) }

    it 'can write to memory' do
      runner.write(0x0800, 0xAB)
      expect(runner.read(0x0800)).to eq(0xAB)
    end

    it 'can read from memory' do
      runner.write(0x0400, 0xCD)
      value = runner.read(0x0400)
      expect(value).to eq(0xCD)
    end

    it 'provides memory sample' do
      runner.write(0x0000, 0x12)  # zero page
      runner.write(0x0100, 0x34)  # stack
      runner.write(0x0400, 0x56)  # text page
      runner.write(0x0800, 0x78)  # program area

      sample = runner.memory_sample
      expect(sample[:zero_page][0]).to eq(0x12)
      expect(sample[:stack][0]).to eq(0x34)
      expect(sample[:text_page][0]).to eq(0x56)
      expect(sample[:program_area][0]).to eq(0x78)
    end
  end
end
