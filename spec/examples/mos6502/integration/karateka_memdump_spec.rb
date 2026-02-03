# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'

require_relative '../../../../examples/mos6502/utilities/apple2/harness'

RSpec.describe 'Karateka memory dump' do
  let(:karateka_bin) do
    File.expand_path('../../../../../examples/mos6502/software/disks/karateka_mem.bin', __FILE__)
  end

  let(:karateka_meta) do
    File.expand_path('../../../../../examples/mos6502/software/disks/karateka_mem_meta.txt', __FILE__)
  end

  describe 'memory dump file' do
    it 'exists' do
      expect(File.exist?(karateka_bin)).to be true
    end

    it 'has correct size (48KB for $0000-$BFFF)' do
      expect(File.size(karateka_bin)).to eq(49152)
    end

    it 'has accompanying metadata file' do
      expect(File.exist?(karateka_meta)).to be true
    end

    it 'metadata contains expected fields' do
      meta = File.read(karateka_meta)
      expect(meta).to include('PC at dump:')
      expect(meta).to include('HIRES: true')
      expect(meta).to include('Display mode: hires')
    end
  end

  describe 'loading into Native ISA simulator' do
    let(:runner) { Apple2Harness::ISARunner.new }
    let(:bytes) { File.binread(karateka_bin).bytes }

    before do
      # Load binary at address 0
      runner.load_ram(bytes, base_addr: 0x0000)

      # Initialize HIRES soft switches
      runner.bus.read(0xC050)  # TXTCLR - graphics mode
      runner.bus.read(0xC052)  # MIXCLR - full screen
      runner.bus.read(0xC054)  # PAGE1 - page 1
      runner.bus.read(0xC057)  # HIRES - hi-res mode

      # Set entry point to $B82A
      entry_point = 0xB82A
      if runner.native?
        runner.cpu.poke(0xFFFC, entry_point & 0xFF)
        runner.cpu.poke(0xFFFD, (entry_point >> 8) & 0xFF)
      else
        runner.bus.write(0xFFFC, entry_point & 0xFF)
        runner.bus.write(0xFFFD, (entry_point >> 8) & 0xFF)
      end

      runner.reset
    end

    it 'sets PC to entry point after reset' do
      expect(runner.cpu_state[:pc]).to eq(0xB82A)
    end

    it 'initializes in HIRES mode' do
      expect(runner.bus.hires_mode?).to be true
    end

    it 'displays hires mode' do
      expect(runner.bus.display_mode).to eq(:hires)
    end

    it 'runs without crashing for 1M cycles' do
      expect { runner.run_steps(1_000_000) }.not_to raise_error
    end

    it 'stays in HIRES mode after running' do
      runner.run_steps(1_000_000)
      expect(runner.bus.hires_mode?).to be true
    end

    it 'can render HIRES graphics' do
      runner.run_steps(1_000_000)
      frame = runner.bus.render_hires_braille(chars_wide: 40, invert: true)
      expect(frame).to be_a(String)
      expect(frame.length).to be > 0
      lines = frame.split("\n")
      expect(lines.length).to eq(48) # 192 rows / 4 rows per braille char
    end
  end

  describe 'loading into Ruby ISA simulator' do
    let(:bus) { MOS6502::Apple2Bus.new('test_bus') }
    let(:runner) { MOS6502::ISASimulator.new(bus) }
    let(:bytes) { File.binread(karateka_bin).bytes }

    before do
      # Load binary at address 0
      bus.load_ram(bytes, base_addr: 0x0000)

      # Initialize HIRES soft switches
      bus.read(0xC050)  # TXTCLR - graphics mode
      bus.read(0xC052)  # MIXCLR - full screen
      bus.read(0xC054)  # PAGE1 - page 1
      bus.read(0xC057)  # HIRES - hi-res mode

      # Set entry point to $B82A
      entry_point = 0xB82A
      bus.write(0xFFFC, entry_point & 0xFF)
      bus.write(0xFFFD, (entry_point >> 8) & 0xFF)

      runner.reset
    end

    it 'sets PC to entry point after reset' do
      expect(runner.pc).to eq(0xB82A)
    end

    it 'initializes in HIRES mode' do
      expect(bus.hires_mode?).to be true
    end

    it 'displays hires mode' do
      expect(bus.display_mode).to eq(:hires)
    end

    it 'runs without crashing for 1M cycles' do
      expect { runner.run_cycles(1_000_000) }.not_to raise_error
    end

    it 'stays in HIRES mode after running' do
      runner.run_cycles(1_000_000)
      expect(bus.hires_mode?).to be true
    end
  end
end
