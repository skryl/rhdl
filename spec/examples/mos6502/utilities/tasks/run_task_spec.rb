# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/mos6502/utilities/tasks/run_task'

RSpec.describe MOS6502::Tasks::RunTask do
  describe '#initialize' do
    it 'accepts options hash' do
      task = described_class.new(mode: :isa, sim: :jit)
      expect(task.instance_variable_get(:@mode)).to eq(:isa)
      expect(task.instance_variable_get(:@sim_backend)).to eq(:jit)
    end

    it 'defaults to isa mode' do
      task = described_class.new
      expect(task.instance_variable_get(:@mode)).to eq(:isa)
    end

    it 'defaults to jit sim backend' do
      task = described_class.new
      expect(task.instance_variable_get(:@sim_backend)).to eq(:jit)
    end

    it 'creates HeadlessRunner internally' do
      task = described_class.new(mode: :isa)
      expect(task.runner).to be_a(MOS6502::HeadlessRunner)
    end
  end

  describe 'HeadlessRunner integration' do
    context 'with isa mode' do
      let(:task) { described_class.new(mode: :isa) }

      it 'creates runner with isa mode' do
        expect(task.runner.mode).to eq(:isa)
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

  describe 'speed calculation' do
    it 'calculates default speed for isa mode' do
      task = described_class.new(mode: :isa)
      speed = task.send(:calculate_default_speed)
      expect(speed).to eq(17_030)
    end

    it 'calculates default speed for hdl interpret mode' do
      task = described_class.new(mode: :hdl, sim: :interpret)
      speed = task.send(:calculate_default_speed)
      expect(speed).to eq(100)
    end

    it 'calculates default speed for hdl jit mode' do
      task = described_class.new(mode: :hdl, sim: :jit)
      speed = task.send(:calculate_default_speed)
      expect(speed).to eq(5_000)
    end

    it 'calculates default speed for hdl compile mode' do
      task = described_class.new(mode: :hdl, sim: :compile)
      speed = task.send(:calculate_default_speed)
      expect(speed).to eq(10_000)
    end

    it 'calculates default speed for netlist mode' do
      begin
        task = described_class.new(mode: :netlist)
        speed = task.send(:calculate_default_speed)
        expect(speed).to eq(10)
      rescue RuntimeError => e
        skip "Netlist mode not implemented: #{e.message}"
      end
    end
  end
end

RSpec.describe MOS6502::HeadlessRunner do
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
    let(:runner) { described_class.with_demo(mode: :isa) }

    it 'creates a HeadlessRunner' do
      expect(runner).to be_a(described_class)
    end

    it 'has demo program loaded' do
      # Verify program is at $0800
      sample = runner.memory_sample
      expect(sample[:program_area][0]).to eq(0xA9)  # LDA immediate
    end

    it 'has reset vector set to $0800' do
      sample = runner.memory_sample
      reset_lo = sample[:reset_vector][0]
      reset_hi = sample[:reset_vector][1]
      reset_addr = (reset_hi << 8) | reset_lo
      expect(reset_addr).to eq(0x0800)
    end
  end

  describe 'PC progression' do
    let(:runner) { described_class.with_demo(mode: :isa) }

    before { runner.reset }

    it 'starts at reset vector address' do
      state = runner.cpu_state
      expect(state[:pc]).to eq(0x0800)
    end

    it 'advances PC after running steps' do
      initial_pc = runner.cpu_state[:pc]
      runner.run_steps(10)
      new_pc = runner.cpu_state[:pc]
      expect(new_pc).to be > initial_pc
    end

    it 'executes instructions and modifies memory' do
      # Run enough to execute the "HELLO" program
      runner.run_steps(50)

      # Check that 'H' was written to $0400
      sample = runner.memory_sample
      expect(sample[:text_page][0]).to eq(0xC8)  # 'H' with high bit
    end

    it 'tracks cycle count' do
      expect(runner.cycle_count).to eq(0)
      runner.run_steps(100)
      expect(runner.cycle_count).to be > 0
    end
  end

  describe 'configuration validation' do
    context 'with isa mode' do
      let(:runner) { described_class.new(mode: :isa) }

      it 'creates runner with isa mode' do
        expect(runner.mode).to eq(:isa)
      end

      it 'reports correct simulator type' do
        expect(runner.simulator_type).to be_a(Symbol)
      end

      it 'backend returns nil for isa mode' do
        expect(runner.backend).to be_nil
      end
    end

    context 'with hdl mode' do
      # Skip if HDL runner not available
      let(:runner) do
        begin
          described_class.new(mode: :hdl, sim: :jit)
        rescue LoadError, StandardError => e
          skip "HDL mode not available: #{e.message}"
        end
      end

      it 'creates runner with hdl mode' do
        expect(runner.mode).to eq(:hdl)
      end

      it 'reports jit backend' do
        expect(runner.backend).to eq(:jit)
      end
    end
  end

  describe 'CPU state access' do
    let(:runner) { described_class.with_demo(mode: :isa) }

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
end
