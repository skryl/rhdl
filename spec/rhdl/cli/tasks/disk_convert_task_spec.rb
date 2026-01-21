# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'

RSpec.describe RHDL::CLI::Tasks::DiskConvertTask do
  let(:temp_dir) { Dir.mktmpdir('rhdl_disk_test') }
  let(:test_disk) { File.join(temp_dir, 'test.dsk') }

  # Create a valid DOS 3.3 disk image (143360 bytes)
  let(:disk_size) { 35 * 16 * 256 }

  before do
    # Create a minimal valid disk image
    disk_data = Array.new(disk_size, 0)
    # Set some recognizable boot sector data
    disk_data[0] = 0x01  # DOS 3.3 signature
    File.binwrite(test_disk, disk_data.pack('C*'))
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'constants' do
    it 'defines disk geometry constants' do
      expect(described_class::TRACKS).to eq(35)
      expect(described_class::SECTORS_PER_TRACK).to eq(16)
      expect(described_class::BYTES_PER_SECTOR).to eq(256)
      expect(described_class::TRACK_SIZE).to eq(4096)
      expect(described_class::DISK_SIZE).to eq(143_360)
    end

    it 'defines DOS 3.3 interleave table' do
      expect(described_class::DOS33_INTERLEAVE).to be_an(Array)
      expect(described_class::DOS33_INTERLEAVE.length).to eq(16)
      expect(described_class::DOS33_INTERLEAVE).to be_frozen
    end

    it 'defines ProDOS interleave table' do
      expect(described_class::PRODOS_INTERLEAVE).to be_an(Array)
      expect(described_class::PRODOS_INTERLEAVE.length).to eq(16)
      expect(described_class::PRODOS_INTERLEAVE).to be_frozen
    end
  end

  describe 'initialization' do
    it 'can be instantiated with no options' do
      expect { described_class.new }.not_to raise_error
    end

    it 'can be instantiated with info option' do
      expect { described_class.new(info: true) }.not_to raise_error
    end

    it 'can be instantiated with convert option' do
      expect { described_class.new(convert: true) }.not_to raise_error
    end

    it 'can be instantiated with extract_boot option' do
      expect { described_class.new(extract_boot: true) }.not_to raise_error
    end

    it 'can be instantiated with extract_tracks option' do
      expect { described_class.new(extract_tracks: true) }.not_to raise_error
    end

    it 'can be instantiated with dump_after_boot option' do
      expect { described_class.new(dump_after_boot: true) }.not_to raise_error
    end

    it 'can be instantiated with disk option' do
      expect { described_class.new(disk: '/path/to/disk.dsk') }.not_to raise_error
    end

    it 'can be instantiated with input option' do
      expect { described_class.new(input: '/path/to/disk.dsk') }.not_to raise_error
    end

    it 'can be instantiated with output option' do
      expect { described_class.new(output: '/path/to/output.bin') }.not_to raise_error
    end

    it 'can be instantiated with base_addr option' do
      expect { described_class.new(base_addr: 0x0800) }.not_to raise_error
    end

    it 'can be instantiated with end_addr option' do
      expect { described_class.new(end_addr: 0xBFFF) }.not_to raise_error
    end

    it 'can be instantiated with start_track option' do
      expect { described_class.new(start_track: 0) }.not_to raise_error
    end

    it 'can be instantiated with end_track option' do
      expect { described_class.new(end_track: 10) }.not_to raise_error
    end

    it 'can be instantiated with prodos option' do
      expect { described_class.new(prodos: true) }.not_to raise_error
    end

    it 'can be instantiated with rom option' do
      expect { described_class.new(rom: '/path/to/rom.bin') }.not_to raise_error
    end

    it 'can be instantiated with max_cycles option' do
      expect { described_class.new(max_cycles: 100_000_000) }.not_to raise_error
    end

    it 'can be instantiated with wait_for_hires option' do
      expect { described_class.new(wait_for_hires: false) }.not_to raise_error
    end

    it 'can be instantiated with combined options' do
      options = {
        disk: '/path/to/disk.dsk',
        output: '/path/to/output.bin',
        start_track: 0,
        end_track: 5,
        prodos: true
      }
      expect { described_class.new(options) }.not_to raise_error
    end
  end

  describe 'options handling' do
    it 'stores all provided options' do
      options = {
        disk: '/path/to/disk.dsk',
        output: '/path/to/output.bin',
        start_track: 1,
        end_track: 10,
        prodos: true,
        base_addr: 0x2000,
        end_addr: 0x9FFF
      }
      task = described_class.new(options)

      expect(task.options[:disk]).to eq('/path/to/disk.dsk')
      expect(task.options[:output]).to eq('/path/to/output.bin')
      expect(task.options[:start_track]).to eq(1)
      expect(task.options[:end_track]).to eq(10)
      expect(task.options[:prodos]).to be true
      expect(task.options[:base_addr]).to eq(0x2000)
      expect(task.options[:end_addr]).to eq(0x9FFF)
    end
  end

  describe '#run' do
    context 'dispatches to correct operation' do
      it 'calls show_disk_info when info option is set' do
        task = described_class.new(info: true, disk: test_disk)
        expect(task).to receive(:show_disk_info)
        task.run
      end

      it 'calls extract_boot_sector when extract_boot option is set' do
        task = described_class.new(extract_boot: true, disk: test_disk)
        expect(task).to receive(:extract_boot_sector)
        task.run
      end

      it 'calls extract_tracks when extract_tracks option is set' do
        task = described_class.new(extract_tracks: true, disk: test_disk)
        expect(task).to receive(:extract_tracks)
        task.run
      end

      it 'calls dump_after_boot when dump_after_boot option is set' do
        task = described_class.new(dump_after_boot: true, disk: test_disk)
        expect(task).to receive(:dump_after_boot)
        task.run
      end

      it 'calls convert_disk_to_binary when convert option is set' do
        task = described_class.new(convert: true, disk: test_disk)
        expect(task).to receive(:convert_disk_to_binary)
        task.run
      end

      it 'defaults to convert_disk_to_binary when no operation is specified' do
        task = described_class.new(disk: test_disk)
        expect(task).to receive(:convert_disk_to_binary)
        task.run
      end
    end
  end

  describe '#show_disk_info' do
    it 'displays disk information' do
      task = described_class.new(info: true, disk: test_disk)
      expect { task.run }.to output(/Disk Image Information/).to_stdout
    end

    it 'shows disk size' do
      task = described_class.new(info: true, disk: test_disk)
      expect { task.run }.to output(/143360 bytes/).to_stdout
    end

    it 'raises error for missing disk file' do
      task = described_class.new(info: true, disk: '/nonexistent/disk.dsk')
      expect { task.run }.to raise_error(/Disk file not found/)
    end

    it 'raises error when no disk specified' do
      task = described_class.new(info: true)
      expect { task.run }.to raise_error(/No input disk file specified/)
    end
  end

  describe '#extract_boot_sector' do
    it 'extracts boot sector to file' do
      output_file = File.join(temp_dir, 'boot.bin')
      task = described_class.new(extract_boot: true, disk: test_disk, output: output_file)

      expect { task.run }.to output(/Extracting boot sector/).to_stdout
      expect(File.exist?(output_file)).to be true
      expect(File.size(output_file)).to eq(256)
    end

    it 'uses default output filename when not specified' do
      task = described_class.new(extract_boot: true, disk: test_disk)

      expect { task.run }.to output(/Extracting boot sector/).to_stdout
      expect(File.exist?(test_disk.sub('.dsk', '_boot.bin'))).to be true
    end
  end

  describe '#extract_tracks' do
    it 'extracts specified tracks to file' do
      output_file = File.join(temp_dir, 'tracks.bin')
      task = described_class.new(
        extract_tracks: true,
        disk: test_disk,
        output: output_file,
        start_track: 0,
        end_track: 2
      )

      expect { task.run }.to output(/Extracting tracks 0-2/).to_stdout
      expect(File.exist?(output_file)).to be true
      # 3 tracks * 16 sectors * 256 bytes = 12288 bytes
      expect(File.size(output_file)).to eq(12_288)
    end

    it 'defaults to tracks 0-2' do
      task = described_class.new(extract_tracks: true, disk: test_disk)

      expect { task.run }.to output(/Extracting tracks 0-2/).to_stdout
    end
  end

  describe '#convert_disk_to_binary' do
    it 'converts disk to binary file' do
      output_file = File.join(temp_dir, 'output.bin')
      task = described_class.new(disk: test_disk, output: output_file)

      expect { task.run }.to output(/Converting disk to binary/).to_stdout
      expect(File.exist?(output_file)).to be true
    end

    it 'uses default memory range when not specified' do
      output_file = File.join(temp_dir, 'output.bin')
      task = described_class.new(disk: test_disk, output: output_file)

      # Base address is $0800 (displayed as $800)
      expect { task.run }.to output(/Base address: \$800/).to_stdout
    end

    it 'respects custom memory range' do
      output_file = File.join(temp_dir, 'output.bin')
      task = described_class.new(
        disk: test_disk,
        output: output_file,
        base_addr: 0x2000,
        end_addr: 0x5FFF
      )

      expect { task.run }.to output(/Base address: \$2000/).to_stdout
    end

    it 'raises error for invalid disk size' do
      # Create an invalid disk file
      invalid_disk = File.join(temp_dir, 'invalid.dsk')
      File.binwrite(invalid_disk, 'too short')

      task = described_class.new(disk: invalid_disk)
      expect { task.run }.to raise_error(/Invalid disk image size/)
    end
  end

  describe '#dump_after_boot' do
    it 'raises error when ROM not specified' do
      task = described_class.new(dump_after_boot: true, disk: test_disk)
      expect { task.run }.to raise_error(/ROM file required/)
    end

    it 'raises error when ROM file not found' do
      task = described_class.new(
        dump_after_boot: true,
        disk: test_disk,
        rom: '/nonexistent/rom.bin'
      )
      expect { task.run }.to raise_error(/ROM file not found/)
    end
  end

  describe 'prodos interleaving' do
    it 'uses ProDOS interleaving when prodos option is set' do
      output_file = File.join(temp_dir, 'output.bin')
      task = described_class.new(
        extract_tracks: true,
        disk: test_disk,
        output: output_file,
        prodos: true
      )

      # ProDOS interleaving should work without error
      expect { task.run }.not_to raise_error
    end
  end
end
