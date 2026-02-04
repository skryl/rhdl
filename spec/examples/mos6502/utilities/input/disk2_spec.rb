# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/mos6502/utilities/input/disk2'

RSpec.describe RHDL::Examples::MOS6502::Disk2 do
  let(:disk) { described_class.new }
  let(:disk_path) { File.join(__dir__, '../../../../../examples/mos6502/software/disks/karateka.dsk') }

  describe '#initialize' do
    it 'starts with motor off' do
      expect(disk.motor_on).to be false
    end

    it 'starts at track 0' do
      expect(disk.track).to eq(0)
    end

    it 'starts in read mode' do
      expect(disk.write_mode).to be false
    end

    it 'starts with drive 0 selected' do
      expect(disk.current_drive).to eq(0)
    end
  end

  describe '#load_disk' do
    it 'loads a valid .dsk file' do
      expect { disk.load_disk(disk_path, drive: 0) }.not_to raise_error
    end

    it 'marks drive as having disk loaded' do
      disk.load_disk(disk_path, drive: 0)
      expect(disk.disk_loaded?(drive: 0)).to be true
      expect(disk.disk_loaded?(drive: 1)).to be false
    end

    it 'raises error for invalid disk size' do
      expect { disk.load_disk([0] * 1000, drive: 0) }.to raise_error(ArgumentError, /Invalid disk image size/)
    end

    it 'can load disk into drive 1' do
      disk.load_disk(disk_path, drive: 1)
      expect(disk.disk_loaded?(drive: 1)).to be true
    end
  end

  describe '#eject_disk' do
    it 'removes disk from drive' do
      disk.load_disk(disk_path, drive: 0)
      disk.eject_disk(drive: 0)
      expect(disk.disk_loaded?(drive: 0)).to be false
    end
  end

  describe '#handles_address?' do
    it 'handles slot 6 addresses ($C0E0-$C0EF)' do
      expect(disk.handles_address?(0xC0E0)).to be true
      expect(disk.handles_address?(0xC0EF)).to be true
    end

    it 'does not handle other addresses' do
      expect(disk.handles_address?(0xC0D0)).to be false
      expect(disk.handles_address?(0xC0F0)).to be false
      expect(disk.handles_address?(0xC000)).to be false
    end
  end

  describe '#access' do
    before { disk.load_disk(disk_path, drive: 0) }

    describe 'motor control' do
      it 'turns motor on when accessing $C0E9' do
        disk.access(0xC0E9)
        expect(disk.motor_on).to be true
      end

      it 'turns motor off when accessing $C0E8' do
        disk.access(0xC0E9)  # turn on first
        disk.access(0xC0E8)
        expect(disk.motor_on).to be false
      end
    end

    describe 'drive selection' do
      it 'selects drive 1 when accessing $C0EA' do
        disk.access(0xC0EA)
        expect(disk.current_drive).to eq(0)
      end

      it 'selects drive 2 when accessing $C0EB' do
        disk.access(0xC0EB)
        expect(disk.current_drive).to eq(1)
      end
    end

    describe 'data reading' do
      before do
        disk.access(0xC0E9)  # motor on
        disk.access(0xC0EE)  # Q7L - read mode
      end

      it 'reads data bytes from track' do
        data = disk.access(0xC0EC)  # Q6L - read data
        expect(data).to be_a(Integer)
        expect(data).to be_between(0, 255)
      end

      it 'returns sync bytes (0xFF) at track start' do
        # First bytes should be gap/sync bytes
        data = disk.access(0xC0EC)
        expect(data).to eq(0xFF)
      end
    end

    describe 'write protect status' do
      it 'returns write protected status ($80) when Q6H + Q7L' do
        disk.access(0xC0ED)  # Q6H
        status = disk.access(0xC0EE)  # Q7L - read status
        expect(status & 0x80).to eq(0x80)
      end
    end
  end

  describe 'constants' do
    it 'has correct disk geometry' do
      expect(described_class::TRACKS).to eq(35)
      expect(described_class::SECTORS_PER_TRACK).to eq(16)
      expect(described_class::BYTES_PER_SECTOR).to eq(256)
      expect(described_class::DISK_SIZE).to eq(143_360)
    end

    it 'has correct slot 6 base address' do
      expect(described_class::BASE_ADDR).to eq(0xC0E0)
    end
  end
end
