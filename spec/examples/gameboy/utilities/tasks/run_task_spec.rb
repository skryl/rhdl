# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/gameboy/utilities/tasks/run_task'

RSpec.describe RHDL::Examples::GameBoy::Tasks::RunTask do
  describe '.create_demo_rom' do
    let(:rom) { described_class.create_demo_rom }

    it 'returns a string of ROM bytes' do
      expect(rom).to be_a(String)
    end

    it 'creates a 32KB ROM' do
      expect(rom.length).to eq(32 * 1024)
    end

    it 'has valid Nintendo logo at 0x104' do
      bytes = rom.bytes
      # First few bytes of Nintendo logo
      expect(bytes[0x104]).to eq(0xCE)
      expect(bytes[0x105]).to eq(0xED)
      expect(bytes[0x106]).to eq(0x66)
      expect(bytes[0x107]).to eq(0x66)
    end

    it 'has title at 0x134' do
      bytes = rom.bytes
      title = bytes[0x134, 9].pack('C*')
      expect(title).to eq("RHDL TEST")
    end

    it 'has valid header checksum at 0x14D' do
      bytes = rom.bytes
      # Calculate expected checksum
      checksum = 0
      (0x134...0x14D).each { |i| checksum = (checksum - bytes[i] - 1) & 0xFF }
      expect(bytes[0x14D]).to eq(checksum)
    end

    it 'has entry point at 0x100' do
      bytes = rom.bytes
      expect(bytes[0x100]).to eq(0x00)  # NOP
      expect(bytes[0x101]).to eq(0xC3)  # JP
      expect(bytes[0x102]).to eq(0x50)  # addr low
      expect(bytes[0x103]).to eq(0x01)  # addr high
    end

    it 'has main program at 0x150' do
      bytes = rom.bytes
      expect(bytes[0x150]).to eq(0x3E)  # LD A, imm
      expect(bytes[0x151]).to eq(0x91)  # $91 (LCD enable)
    end
  end

  describe '#initialize' do
    it 'accepts options hash' do
      task = described_class.new(mode: :ruby, sim: :ruby)
      expect(task.options[:mode]).to eq(:ruby)
      expect(task.options[:sim]).to eq(:ruby)
    end

    it 'defaults to empty options' do
      task = described_class.new
      expect(task.options).to eq({})
    end
  end

  describe '#run with headless mode' do
    let(:task) do
      described_class.new(
        headless: true,
        demo: true,
        mode: :ruby,
        sim: :ruby,
        cycles: 100
      )
    end

    it 'runs without terminal UI' do
      result = task.run
      expect(result).to be_a(Hash)
      expect(result).to include(:pc, :a, :cycles)
    end

    it 'returns CPU state after running' do
      result = task.run
      expect(result[:cycles]).to eq(100)
    end

    it 'uses HeadlessRunner internally' do
      task.run
      expect(task.runner).to be_a(RHDL::Examples::GameBoy::HeadlessRunner)
    end
  end

  describe 'option handling' do
    context 'with demo option' do
      let(:task) { described_class.new(headless: true, demo: true, mode: :ruby, sim: :ruby, cycles: 10) }

      it 'loads demo ROM' do
        result = task.run
        expect(result[:cycles]).to eq(10)
      end
    end

    context 'with rom_bytes option' do
      let(:rom) { described_class.create_demo_rom }
      let(:task) { described_class.new(headless: true, rom_bytes: rom, mode: :ruby, sim: :ruby, cycles: 10) }

      it 'loads ROM from bytes' do
        result = task.run
        expect(result[:cycles]).to eq(10)
      end
    end

    context 'with invalid options' do
      let(:task) { described_class.new(headless: true, mode: :ruby, sim: :ruby, cycles: 10) }

      it 'raises error when no ROM specified' do
        expect { task.run }.to raise_error(ArgumentError, /No ROM specified/)
      end
    end

    context 'with mode options' do
      it 'accepts :ruby mode' do
        task = described_class.new(headless: true, demo: true, mode: :ruby, sim: :ruby, cycles: 10)
        task.run
        expect(task.runner.mode).to eq(:ruby)
      end

      it 'accepts different sim backends' do
        task = described_class.new(headless: true, demo: true, mode: :ruby, sim: :ruby, cycles: 10)
        task.run
        expect(task.runner.sim_backend).to eq(:ruby)
      end
    end
  end

  describe 'HeadlessRunner integration' do
    let(:task) { described_class.new(headless: true, demo: true, mode: :ruby, sim: :ruby, cycles: 50) }

    before { task.run }

    it 'creates runner with correct mode' do
      expect(task.runner.mode).to eq(:ruby)
    end

    it 'creates runner with correct sim backend' do
      expect(task.runner.sim_backend).to eq(:ruby)
    end

    it 'runner reports correct simulator type' do
      expect(task.runner.simulator_type).to eq(:hdl_ruby)
    end

    it 'runner tracks cycle count' do
      expect(task.runner.cycle_count).to eq(50)
    end

    it 'provides access to CPU state' do
      state = task.runner.cpu_state
      expect(state).to include(:pc, :a, :f)
    end
  end

  describe 'PC progression' do
    let(:task) { described_class.new(headless: true, demo: true, mode: :ruby, sim: :ruby, cycles: 10) }

    it 'has valid PC after running' do
      result = task.run
      # PC should be a valid 16-bit address
      expect(result[:pc]).to be_a(Integer)
      expect(result[:pc]).to be_between(0x0000, 0xFFFF)
    end

    it 'executes instructions and changes cycle count' do
      result = task.run
      expect(result[:cycles]).to eq(10)
    end

    it 'cycle count increases with more cycles' do
      task1 = described_class.new(headless: true, demo: true, mode: :ruby, sim: :ruby, cycles: 10)
      task2 = described_class.new(headless: true, demo: true, mode: :ruby, sim: :ruby, cycles: 100)

      result1 = task1.run
      result2 = task2.run

      # More cycles should result in more execution
      expect(result2[:cycles]).to be > result1[:cycles]
    end

    it 'provides valid CPU state' do
      result = task.run
      expect(result).to include(:pc, :a, :f, :cycles)
      expect(result[:a]).to be_between(0, 255)
      expect(result[:f]).to be_between(0, 255)
    end
  end

  describe 'configuration validation' do
    context 'with ruby mode and ruby backend' do
      let(:task) { described_class.new(headless: true, demo: true, mode: :ruby, sim: :ruby, cycles: 10) }

      it 'creates runner with ruby mode' do
        task.run
        expect(task.runner.mode).to eq(:ruby)
      end

      it 'creates runner with ruby backend' do
        task.run
        expect(task.runner.sim_backend).to eq(:ruby)
      end

      it 'reports hdl_ruby simulator type' do
        task.run
        expect(task.runner.simulator_type).to eq(:hdl_ruby)
      end

      it 'returns false for native?' do
        task.run
        expect(task.runner.native?).to eq(false)
      end
    end
  end

  describe 'constants' do
    it 'defines screen dimensions' do
      expect(described_class::SCREEN_WIDTH).to eq(160)
      expect(described_class::SCREEN_HEIGHT).to eq(144)
    end

    it 'defines LCD character dimensions' do
      expect(described_class::LCD_CHARS_WIDE).to eq(80)
      expect(described_class::LCD_CHARS_TALL).to eq(36)
    end

    it 'defines ANSI escape codes' do
      expect(described_class::CLEAR_SCREEN).to include("\e[")
      expect(described_class::HIDE_CURSOR).to include("\e[")
      expect(described_class::SHOW_CURSOR).to include("\e[")
    end
  end
end
