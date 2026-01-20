# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/mos6502/utilities/apple2_harness'

RSpec.describe 'Apple2Bus disk integration' do
  let(:runner) { Apple2Harness::ISARunner.new }
  let(:bus) { runner.bus }
  let(:disk_path) { File.join(__dir__, '../../../examples/mos6502/software/disks/karateka.dsk') }

  describe 'disk loading through harness' do
    it 'loads disk into drive 0' do
      runner.load_disk(disk_path, drive: 0)
      expect(runner.disk_loaded?(drive: 0)).to be true
    end

    it 'exposes disk controller through bus' do
      expect(bus.disk_controller).to be_a(MOS6502::Disk2)
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
      bus.write(0xFFFC, 0x00)  # Reset vector low
      bus.write(0xFFFD, 0x08)  # Reset vector high
      runner.reset

      # Run until BRK
      runner.run_until(max_cycles: 1000) { runner.cpu.pc == 0x0803 }

      expect(bus.disk_controller.motor_on).to be true
    end
  end
end
