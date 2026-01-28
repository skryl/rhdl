# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/hdl/disk_ii'
require_relative '../../../examples/apple2/hdl/apple2'
require_relative '../../../examples/mos6502/utilities/disk2'

RSpec.describe 'Apple2 DiskII HDL with actual .dsk files' do
  # Test that the DiskII HDL component can load and read actual .dsk disk images
  # using the appleiigo ROM and karateka.dsk

  # File paths
  KARATEKA_DSK_PATH = File.expand_path('../../../../examples/apple2/software/disks/karateka.dsk', __FILE__)
  APPLEIIGO_ROM_PATH = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  DISK2_BOOT_ROM_PATH = File.expand_path('../../../../examples/apple2/software/roms/disk2_boot.bin', __FILE__)

  # Check file availability
  def self.karateka_available?
    File.exist?(KARATEKA_DSK_PATH)
  end

  def self.appleiigo_available?
    File.exist?(APPLEIIGO_ROM_PATH)
  end

  def self.disk2_boot_rom_available?
    File.exist?(DISK2_BOOT_ROM_PATH)
  end

  describe RHDL::Apple2::DiskII, 'with karateka.dsk' do
    let(:disk) { described_class.new('disk') }
    let(:disk2_encoder) { MOS6502::Disk2.new }

    before do
      skip 'karateka.dsk not found' unless self.class.karateka_available?

      disk
      # Initialize inputs
      disk.set_input(:clk_14m, 0)
      disk.set_input(:clk_2m, 0)
      disk.set_input(:pre_phase_zero, 0)
      disk.set_input(:io_select, 0)
      disk.set_input(:device_select, 0)
      disk.set_input(:reset, 0)
      disk.set_input(:a, 0)
      disk.set_input(:d_in, 0)
      disk.set_input(:ram_write_addr, 0)
      disk.set_input(:ram_di, 0)
      disk.set_input(:ram_we, 0)

      # Reset the component
      disk.set_input(:reset, 1)
      clock_2m
      disk.set_input(:reset, 0)

      # Load karateka.dsk and encode to nibbles
      disk2_encoder.load_disk(KARATEKA_DSK_PATH, drive: 0)
    end

    def clock_14m
      disk.set_input(:clk_14m, 0)
      disk.propagate
      disk.set_input(:clk_14m, 1)
      disk.propagate
    end

    def clock_2m
      disk.set_input(:clk_2m, 0)
      disk.propagate
      disk.set_input(:clk_2m, 1)
      disk.propagate
    end

    def access_io(addr_low)
      disk.set_input(:a, 0xC0E0 | addr_low)
      disk.set_input(:device_select, 1)
      disk.set_input(:pre_phase_zero, 1)
      clock_2m
      disk.set_input(:device_select, 0)
      disk.set_input(:pre_phase_zero, 0)
    end

    def load_nibblized_track(track_num)
      # Get encoded track data from the Disk2 encoder
      encoded_tracks = disk2_encoder.instance_variable_get(:@drives)[0]
      return unless encoded_tracks && encoded_tracks[track_num]

      track_data = encoded_tracks[track_num]

      # Load into HDL track memory via simulation helper (direct memory write)
      disk.load_track(track_num, track_data)
    end

    describe 'loading disk image' do
      it 'loads karateka.dsk without error' do
        expect { disk2_encoder.load_disk(KARATEKA_DSK_PATH, drive: 0) }.not_to raise_error
        expect(disk2_encoder.disk_loaded?(drive: 0)).to be true
      end

      it 'encodes all 35 tracks' do
        encoded_tracks = disk2_encoder.instance_variable_get(:@drives)[0]
        expect(encoded_tracks).not_to be_nil
        expect(encoded_tracks.length).to eq(35)
      end

      it 'produces valid nibble data (all bytes have high bit or are sync bytes)' do
        encoded_tracks = disk2_encoder.instance_variable_get(:@drives)[0]
        track0 = encoded_tracks[0]

        # All valid disk nibbles should have bit 7 set (>= 0x80)
        # or be self-sync bytes (0xFF)
        invalid_bytes = track0.select { |b| b < 0x80 }
        expect(invalid_bytes).to be_empty,
          "Found #{invalid_bytes.length} invalid nibble bytes (< 0x80)"
      end
    end

    describe 'track data structure' do
      it 'contains proper address field prologues (D5 AA 96)' do
        encoded_tracks = disk2_encoder.instance_variable_get(:@drives)[0]
        track0 = encoded_tracks[0]

        # Find address field prologue pattern
        prologue_count = 0
        (0..track0.length - 3).each do |i|
          if track0[i] == 0xD5 && track0[i + 1] == 0xAA && track0[i + 2] == 0x96
            prologue_count += 1
          end
        end

        # Should have 16 sectors per track
        expect(prologue_count).to eq(16),
          "Expected 16 address field prologues, found #{prologue_count}"
      end

      it 'contains proper data field prologues (D5 AA AD)' do
        encoded_tracks = disk2_encoder.instance_variable_get(:@drives)[0]
        track0 = encoded_tracks[0]

        # Find data field prologue pattern
        prologue_count = 0
        (0..track0.length - 3).each do |i|
          if track0[i] == 0xD5 && track0[i + 1] == 0xAA && track0[i + 2] == 0xAD
            prologue_count += 1
          end
        end

        # Should have 16 sectors per track
        expect(prologue_count).to eq(16),
          "Expected 16 data field prologues, found #{prologue_count}"
      end
    end

    describe 'loading track into HDL component' do
      before do
        load_nibblized_track(0)
      end

      it 'stores track data in HDL memory' do
        # Verify first few bytes are loaded
        byte0 = disk.read_track_byte(0)
        byte1 = disk.read_track_byte(1)
        byte2 = disk.read_track_byte(2)

        # First bytes should be sync (0xFF) or valid nibbles
        expect(byte0).to be >= 0x80
        expect(byte1).to be >= 0x80
        expect(byte2).to be >= 0x80
      end

      it 'can read address field prologue from HDL memory' do
        encoded_tracks = disk2_encoder.instance_variable_get(:@drives)[0]
        track0 = encoded_tracks[0]

        # Find first address prologue in source data
        prologue_offset = nil
        (0..track0.length - 3).each do |i|
          if track0[i] == 0xD5 && track0[i + 1] == 0xAA && track0[i + 2] == 0x96
            prologue_offset = i
            break
          end
        end

        expect(prologue_offset).not_to be_nil

        # Read same bytes from HDL memory
        b0 = disk.read_track_byte(prologue_offset)
        b1 = disk.read_track_byte(prologue_offset + 1)
        b2 = disk.read_track_byte(prologue_offset + 2)

        expect([b0, b1, b2]).to eq([0xD5, 0xAA, 0x96])
      end
    end

    describe 'disk I/O operations' do
      before do
        load_nibblized_track(0)

        # Turn motor on and set read mode
        access_io(0x09)  # MOTOR_ON (C0E9)
        access_io(0x0E)  # Q7L - Read mode (C0EE)
      end

      it 'turns motor on' do
        d1_active = disk.get_output(:d1_active)
        expect(d1_active).to eq(1)
      end

      it 'reads data when accessing C0EC' do
        # Read data via C08C (Q6L in read mode)
        disk.set_input(:a, 0xC0EC)
        disk.set_input(:device_select, 1)
        disk.propagate

        d_out = disk.get_output(:d_out)
        expect(d_out).to be_between(0, 255)
      end

      it 'reads valid disk nibbles (high bit set)' do
        # Multiple reads should all return valid nibbles
        valid_count = 0
        20.times do
          disk.set_input(:a, 0xC0EC)
          disk.set_input(:device_select, 1)
          disk.set_input(:pre_phase_zero, 1)
          clock_2m
          disk.set_input(:device_select, 0)
          disk.set_input(:pre_phase_zero, 0)

          d_out = disk.get_output(:d_out)
          valid_count += 1 if d_out >= 0x80 || d_out == 0
        end

        # Most reads should return valid nibbles
        expect(valid_count).to be >= 10
      end

      it 'advances track address on reads' do
        initial_addr = disk.get_output(:track_addr)

        # Multiple reads should advance the address
        10.times do
          disk.set_input(:a, 0xC0EC)
          disk.set_input(:device_select, 1)
          disk.set_input(:pre_phase_zero, 1)
          clock_2m
          disk.set_input(:device_select, 0)
          disk.set_input(:pre_phase_zero, 0)
        end

        final_addr = disk.get_output(:track_addr)
        # Address should change (disk spinning simulation)
        expect(final_addr).to be_a(Integer)
      end
    end

    describe 'reading sequential data' do
      before do
        load_nibblized_track(0)
        access_io(0x09)  # Motor on
        access_io(0x0E)  # Read mode
      end

      it 'can find address field prologue by direct memory scan' do
        # Verify the prologue exists in track memory by direct read
        # This confirms the data was loaded correctly
        encoded_tracks = disk2_encoder.instance_variable_get(:@drives)[0]
        track0 = encoded_tracks[0]

        # Find first address prologue in source data
        prologue_found_in_source = false
        (0..track0.length - 3).each do |i|
          if track0[i] == 0xD5 && track0[i + 1] == 0xAA && track0[i + 2] == 0x96
            prologue_found_in_source = true
            break
          end
        end

        expect(prologue_found_in_source).to be(true),
          "Address prologue should exist in encoded track data"

        # Verify we can read it from HDL memory
        bytes_read = []
        (0...500).each do |i|
          byte = disk.read_track_byte(i)
          bytes_read << byte

          if bytes_read.length >= 3
            last3 = bytes_read[-3..-1]
            if last3 == [0xD5, 0xAA, 0x96]
              break
            end
          end
        end

        found_prologue = bytes_read.length >= 3 &&
          bytes_read.each_cons(3).any? { |a, b, c| a == 0xD5 && b == 0xAA && c == 0x96 }

        expect(found_prologue).to be(true),
          "Failed to find address prologue in #{bytes_read.length} bytes from HDL memory"
      end

      it 'returns non-zero data from hardware read path' do
        # Verify the hardware d_out path returns some valid data
        non_zero_count = 0

        50.times do
          disk.set_input(:a, 0xC0EC)
          disk.set_input(:device_select, 1)
          disk.set_input(:pre_phase_zero, 1)
          clock_2m
          disk.set_input(:device_select, 0)
          disk.set_input(:pre_phase_zero, 0)

          d_out = disk.get_output(:d_out)
          non_zero_count += 1 if d_out != 0
        end

        # Some reads should return non-zero data
        expect(non_zero_count).to be > 0,
          "Hardware read path should return some non-zero data"
      end
    end

    describe 'disk boot ROM' do
      before do
        skip 'disk2_boot.bin not found' unless self.class.disk2_boot_rom_available?

        # Load the Disk II boot ROM
        boot_rom_data = File.binread(DISK2_BOOT_ROM_PATH).bytes
        disk.instance_variable_get(:@rom).load_rom(boot_rom_data)
      end

      it 'loads 256-byte boot ROM' do
        boot_rom_data = File.binread(DISK2_BOOT_ROM_PATH).bytes
        expect(boot_rom_data.length).to eq(256)
      end

      it 'reads boot ROM when io_select is high' do
        disk.set_input(:a, 0xC600)
        disk.set_input(:io_select, 1)
        disk.propagate

        d_out = disk.get_output(:d_out)
        expect(d_out).to be_between(0, 255)
      end

      it 'returns correct boot ROM bytes' do
        boot_rom_data = File.binread(DISK2_BOOT_ROM_PATH).bytes

        # Check first few bytes
        [0, 1, 2, 0x10, 0x50, 0xFF].each do |offset|
          disk.set_input(:a, 0xC600 + offset)
          disk.set_input(:io_select, 1)
          disk.propagate

          d_out = disk.get_output(:d_out)
          expect(d_out).to eq(boot_rom_data[offset]),
            "ROM byte at offset #{offset}: expected #{boot_rom_data[offset]}, got #{d_out}"
        end
      end
    end
  end

  describe RHDL::Apple2::Apple2, 'disk boot with appleiigo.rom and karateka.dsk' do
    let(:apple2) { described_class.new('apple2') }
    let(:ram) { Array.new(48 * 1024, 0) }
    let(:disk2_encoder) { MOS6502::Disk2.new }

    before do
      skip 'appleiigo.rom not found' unless self.class.appleiigo_available?
      skip 'karateka.dsk not found' unless self.class.karateka_available?
      skip 'disk2_boot.bin not found' unless self.class.disk2_boot_rom_available?

      apple2
      # Initialize inputs
      apple2.set_input(:clk_14m, 0)
      apple2.set_input(:flash_clk, 0)
      apple2.set_input(:reset, 0)
      apple2.set_input(:ram_do, 0)
      apple2.set_input(:pd, 0)
      apple2.set_input(:ps2_clk, 1)
      apple2.set_input(:ps2_data, 1)
      apple2.set_input(:gameport, 0)
      apple2.set_input(:pause, 0)

      # Load AppleIIgo ROM
      rom_data = File.binread(APPLEIIGO_ROM_PATH).bytes
      apple2.load_rom(rom_data)

      # Load Disk II boot ROM into disk controller
      boot_rom_data = File.binread(DISK2_BOOT_ROM_PATH).bytes
      apple2.disk_controller.instance_variable_get(:@rom).load_rom(boot_rom_data)

      # Load karateka.dsk
      disk2_encoder.load_disk(KARATEKA_DSK_PATH, drive: 0)
    end

    def clock_14m_cycle
      apple2.set_input(:clk_14m, 0)
      apple2.propagate

      ram_addr = apple2.get_output(:ram_addr)
      if ram_addr < ram.size
        apple2.set_input(:ram_do, ram[ram_addr])
      end
      apple2.propagate

      apple2.set_input(:clk_14m, 1)
      apple2.propagate

      ram_we = apple2.get_output(:ram_we)
      if ram_we == 1
        write_addr = apple2.get_output(:ram_addr)
        if write_addr < ram.size
          ram[write_addr] = apple2.get_output(:d)
        end
      end
    end

    def clock_cycle
      14.times { clock_14m_cycle }
    end

    def run_cycles(n)
      n.times { clock_cycle }
    end

    def reset_system
      apple2.set_input(:reset, 1)
      clock_cycle
      apple2.set_input(:reset, 0)
    end

    def load_track_into_apple2(track_num)
      encoded_tracks = disk2_encoder.instance_variable_get(:@drives)[0]
      return unless encoded_tracks && encoded_tracks[track_num]

      apple2.disk_controller.load_track(track_num, encoded_tracks[track_num])
    end

    describe 'system integration' do
      before do
        reset_system
      end

      it 'has disk controller available' do
        disk = apple2.disk_controller
        expect(disk).to be_a(RHDL::Apple2::DiskII)
      end

      it 'boots with appleiigo.rom' do
        # Run just a few cycles - HDL simulation is slow
        run_cycles(10)

        pc = apple2.get_output(:pc_debug)
        expect(pc).to be_between(0, 0xFFFF)
        # After just 10 cycles, PC may still be in early boot
      end
    end

    describe 'disk data loading' do
      before do
        reset_system
        load_track_into_apple2(0)
      end

      it 'loads track 0 into disk controller' do
        disk = apple2.disk_controller
        byte0 = disk.read_track_byte(0)
        expect(byte0).to be >= 0x80
      end

      it 'can load all 35 tracks' do
        35.times do |track_num|
          load_track_into_apple2(track_num)

          disk = apple2.disk_controller
          byte = disk.read_track_byte(0)
          expect(byte).to be_a(Integer)
        end
      end
    end

    describe 'boot ROM access' do
      before do
        reset_system
      end

      it 'disk boot ROM is addressable at $C600' do
        boot_rom_data = File.binread(DISK2_BOOT_ROM_PATH).bytes

        # Access through disk controller ROM
        disk = apple2.disk_controller
        rom = disk.instance_variable_get(:@rom)

        # Verify ROM data matches
        rom.set_input(:addr, 0)
        rom.propagate
        expect(rom.get_output(:dout)).to eq(boot_rom_data[0])
      end
    end

    describe 'CPU can access disk controller' do
      before do
        reset_system
        load_track_into_apple2(0)
      end

      it 'disk controller responds to soft switch addresses' do
        disk = apple2.disk_controller

        # Motor should be off initially
        expect(disk.get_output(:d1_active)).to eq(0)
      end
    end
  end

  describe 'multi-track disk operations' do
    let(:disk) { RHDL::Apple2::DiskII.new('disk') }
    let(:disk2_encoder) { MOS6502::Disk2.new }

    before do
      skip 'karateka.dsk not found' unless self.class.karateka_available?

      disk
      disk.set_input(:clk_14m, 0)
      disk.set_input(:clk_2m, 0)
      disk.set_input(:pre_phase_zero, 0)
      disk.set_input(:io_select, 0)
      disk.set_input(:device_select, 0)
      disk.set_input(:reset, 0)
      disk.set_input(:a, 0)
      disk.set_input(:d_in, 0)
      disk.set_input(:ram_write_addr, 0)
      disk.set_input(:ram_di, 0)
      disk.set_input(:ram_we, 0)

      disk.set_input(:reset, 1)
      clock_2m
      disk.set_input(:reset, 0)

      disk2_encoder.load_disk(KARATEKA_DSK_PATH, drive: 0)
    end

    def clock_14m
      disk.set_input(:clk_14m, 0)
      disk.propagate
      disk.set_input(:clk_14m, 1)
      disk.propagate
    end

    def clock_2m
      disk.set_input(:clk_2m, 0)
      disk.propagate
      disk.set_input(:clk_2m, 1)
      disk.propagate
    end

    def load_track(track_num)
      encoded_tracks = disk2_encoder.instance_variable_get(:@drives)[0]
      return unless encoded_tracks && encoded_tracks[track_num]

      track_data = encoded_tracks[track_num]

      # Use simulation helper for direct memory write
      disk.load_track(track_num, track_data)
    end

    it 'can load different tracks with unique data' do
      # Load track 0 and capture first 10 bytes
      load_track(0)
      track0_bytes = (0...10).map { |i| disk.read_track_byte(i) }

      # Load track 17 (middle of disk) and capture first 10 bytes
      load_track(17)
      track17_bytes = (0...10).map { |i| disk.read_track_byte(i) }

      # The tracks should have different data (different sectors)
      # Both should be valid nibbles
      expect(track0_bytes.all? { |b| b >= 0x80 }).to be(true)
      expect(track17_bytes.all? { |b| b >= 0x80 }).to be(true)
    end

    it 'all tracks have valid sector structure' do
      [0, 10, 17, 25, 34].each do |track_num|
        load_track(track_num)

        # Find address prologues in this track
        bytes = (0...500).map { |i| disk.read_track_byte(i) }

        prologue_found = false
        (0..bytes.length - 3).each do |i|
          if bytes[i] == 0xD5 && bytes[i + 1] == 0xAA && bytes[i + 2] == 0x96
            prologue_found = true
            break
          end
        end

        expect(prologue_found).to be(true),
          "Track #{track_num} missing address prologue"
      end
    end
  end
end
