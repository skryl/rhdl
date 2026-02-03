# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/mos6502/utilities/apple2/harness'

RSpec.describe 'Apple2Bus disk integration' do
  let(:runner) { RHDL::Examples::MOS6502::Apple2Harness::ISARunner.new }
  let(:bus) { runner.bus }
  let(:disk_path) { File.join(__dir__, '../../../../../examples/mos6502/software/disks/karateka.dsk') }

  describe 'disk loading through harness' do
    it 'loads disk into drive 0' do
      runner.load_disk(disk_path, drive: 0)
      expect(runner.disk_loaded?(drive: 0)).to be true
    end

    it 'exposes disk controller through bus' do
      expect(bus.disk_controller).to be_a(RHDL::Examples::MOS6502::Disk2)
    end
  end

  describe 'disk I/O through bus' do
    before { runner.load_disk(disk_path, drive: 0) }

    it 'routes disk controller addresses through bus' do
      # Turn motor on via bus read
      bus.read(0xC0E9)
      expect(bus.disk_controller.motor_on).to be true
    end

    it 'reads disk data through bus' do
      bus.read(0xC0E9)  # motor on
      bus.read(0xC0EE)  # read mode
      data = bus.read(0xC0EC)  # read data
      expect(data).to be_a(Integer)
    end
  end

  describe 'CPU disk access simulation' do
    before { runner.load_disk(disk_path, drive: 0) }

    it 'allows CPU to access disk controller' do
      # Write a small program that turns on the disk motor
      # LDA $C0E9 (turn motor on)
      # BRK
      program = [
        0xAD, 0xE9, 0xC0,  # LDA $C0E9
        0x00               # BRK
      ]
      runner.load_ram(program, base_addr: 0x0800)
      runner.write_memory(0xFFFC, 0x00)  # Reset vector low
      runner.write_memory(0xFFFD, 0x08)  # Reset vector high
      runner.reset

      # Run until BRK
      runner.run_until(max_cycles: 1000) { runner.cpu.pc == 0x0803 }

      expect(bus.disk_controller.motor_on).to be true
    end
  end

  describe 'video soft switches' do
    it 'starts in text mode' do
      expect(bus.video[:text]).to be true
      expect(bus.video[:hires]).to be false
      expect(bus.hires_mode?).to be false
      expect(bus.text_mode?).to be true
    end

    it 'switches to graphics mode when $C050 is accessed' do
      bus.read(0xC050)  # Access GRAPHICS soft switch
      expect(bus.video[:text]).to be false
    end

    it 'switches to hires mode when $C057 is accessed' do
      bus.read(0xC057)  # Access HIRES soft switch
      expect(bus.video[:hires]).to be true
    end

    it 'returns hires_mode? true when both switches are set' do
      bus.read(0xC050)  # Graphics mode (text off)
      bus.read(0xC057)  # Hires on
      expect(bus.hires_mode?).to be true
      expect(bus.display_mode).to eq(:hires)
    end

    it 'can switch via write as well as read' do
      bus.write(0xC050, 0)  # Graphics mode (text off)
      bus.write(0xC057, 0)  # Hires on
      expect(bus.hires_mode?).to be true
    end

    it 'allows CPU to switch video modes' do
      # Program that switches to hires mode
      program = [
        0xAD, 0x50, 0xC0,  # LDA $C050 (graphics mode)
        0xAD, 0x57, 0xC0,  # LDA $C057 (hires on)
        0x00               # BRK
      ]
      runner.load_ram(program, base_addr: 0x0800)
      runner.write_memory(0xFFFC, 0x00)  # Reset vector low
      runner.write_memory(0xFFFD, 0x08)  # Reset vector high
      runner.reset

      # Initially in text mode
      expect(bus.hires_mode?).to be false

      # Run the program
      runner.run_until(max_cycles: 100) { runner.halted? }

      # Sync video state from native CPU to bus (native CPU handles soft switches internally)
      runner.sync_video_state

      # Now should be in hires mode
      expect(bus.hires_mode?).to be true
    end
  end
end
