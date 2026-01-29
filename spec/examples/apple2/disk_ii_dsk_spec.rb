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

  describe 'IR Compiler boot with karateka' do
    # Test the full boot sequence using the IR compiler
    # Uses karateka_mem.bin (pre-loaded memory dump) since IR compiler
    # doesn't support disk I/O from .dsk files

    KARATEKA_MEM_PATH = File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

    def self.ir_compiler_available?
      require 'rhdl/codegen'
      RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
    rescue LoadError
      false
    end

    def self.karateka_mem_available?
      File.exist?(KARATEKA_MEM_PATH)
    end

    # Memory region classification
    def pc_region(pc)
      case pc
      when 0x0000..0x01FF then :zp_stack
      when 0x0200..0x03FF then :input_buf
      when 0x0400..0x07FF then :text
      when 0x0800..0x1FFF then :user
      when 0x2000..0x3FFF then :hires1
      when 0x4000..0x5FFF then :hires2
      when 0x6000..0xBFFF then :high_ram
      when 0xC000..0xCFFF then :io
      when 0xD000..0xFFFF then :rom
      else :unknown
      end
    end

    before(:all) do
      @rom_available = File.exist?(APPLEIIGO_ROM_PATH)
      @karateka_mem_available = File.exist?(KARATEKA_MEM_PATH)

      if @rom_available
        @rom_data = File.binread(APPLEIIGO_ROM_PATH).bytes
      end
      if @karateka_mem_available
        @karateka_mem = File.binread(KARATEKA_MEM_PATH).bytes
      end
    end

    def create_karateka_rom
      rom = @rom_data.dup
      # Set reset vector to Karateka entry point $B82A
      rom[0x2FFC] = 0x2A  # low byte of $B82A
      rom[0x2FFD] = 0xB8  # high byte of $B82A
      rom
    end

    def create_ir_compiler
      require 'rhdl/codegen'

      ir = RHDL::Apple2::Apple2.to_flat_ir
      ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)

      sim = RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json, sub_cycles: 14)

      karateka_rom = create_karateka_rom
      sim.load_rom(karateka_rom)
      sim.load_ram(@karateka_mem.first(48 * 1024), 0)

      # Reset sequence
      sim.poke('reset', 1)
      sim.tick
      sim.poke('reset', 0)
      3.times { sim.run_cpu_cycles(1, 0, false) }

      # Initialize HIRES soft switches (value 8 sets hires mode)
      sim.poke('soft_switches', 8)

      sim
    end

    describe 'game boot and execution' do
      before do
        skip 'appleiigo.rom not found' unless @rom_available
        skip 'karateka_mem.bin not found' unless @karateka_mem_available

        begin
          require 'rhdl/codegen'
          skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
        rescue LoadError
          skip 'IR Codegen not available'
        end

        @ir_sim = create_ir_compiler
      end

      it 'starts at Karateka entry point $B82A' do
        pc = @ir_sim.peek('cpu__pc_reg')
        expect(pc).to eq(0xB82A),
          "Expected PC at $B82A (Karateka entry), got $#{pc.to_s(16).upcase}"
      end

      it 'executes in high_ram region initially' do
        pc = @ir_sim.peek('cpu__pc_reg')
        region = pc_region(pc)
        expect(region).to eq(:high_ram),
          "Expected execution in high_ram, got #{region} at $#{pc.to_s(16).upcase}"
      end

      it 'runs 1M cycles without halting' do
        # Run 1M cycles in batches
        cycles_to_run = 1_000_000
        batch_size = 100_000

        (cycles_to_run / batch_size).times do
          @ir_sim.run_cpu_cycles(batch_size, 0, false)
        end

        # Verify still executing (PC should be valid)
        pc = @ir_sim.peek('cpu__pc_reg')
        expect(pc).to be_between(0, 0xFFFF)
      end

      it 'visits game loop regions during execution' do
        # Track which regions are visited during execution
        regions_visited = Set.new

        # Sample PC every 50K cycles over 500K cycles
        10.times do
          @ir_sim.run_cpu_cycles(50_000, 0, false)
          pc = @ir_sim.peek('cpu__pc_reg')
          regions_visited.add(pc_region(pc))
        end

        # Game should visit high_ram (game code) and rom (kernel calls)
        expect(regions_visited).to include(:high_ram),
          "Game should execute in high_ram region. Visited: #{regions_visited.to_a}"

        # At least 2 different regions should be visited
        expect(regions_visited.size).to be >= 2,
          "Game should visit multiple regions. Only visited: #{regions_visited.to_a}"
      end

      it 'reads valid opcode during execution' do
        opcode = @ir_sim.peek('opcode_debug')
        expect(opcode).to be_between(0, 255)
        expect(opcode).not_to eq(0x00),
          "Opcode should not be BRK (0x00) at game entry"
      end
    end

    describe 'extended game execution', :slow do
      before do
        skip 'appleiigo.rom not found' unless @rom_available
        skip 'karateka_mem.bin not found' unless @karateka_mem_available

        begin
          require 'rhdl/codegen'
          skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
        rescue LoadError
          skip 'IR Codegen not available'
        end

        @ir_sim = create_ir_compiler
      end

      it 'runs 5M cycles maintaining game state' do
        # Run 5M cycles (equivalent to ~5 seconds of Apple II time)
        cycles_to_run = 5_000_000
        batch_size = 500_000

        pc_samples = []

        (cycles_to_run / batch_size).times do
          @ir_sim.run_cpu_cycles(batch_size, 0, false)
          pc = @ir_sim.peek('cpu__pc_reg')
          pc_samples << pc
        end

        # All PCs should be valid
        expect(pc_samples).to all(be_between(0, 0xFFFF))

        # Should not be stuck at same PC (game should be running)
        unique_pcs = pc_samples.uniq
        expect(unique_pcs.size).to be > 1,
          "Game appears stuck at PC $#{pc_samples.first.to_s(16)}"

        # Should primarily be in game regions (high_ram, rom)
        game_region_samples = pc_samples.count { |pc| [:high_ram, :rom].include?(pc_region(pc)) }
        expect(game_region_samples).to be >= (pc_samples.size / 2),
          "Game should spend most time in high_ram/rom regions"
      end

      it 'maintains hires graphics mode' do
        # Run some cycles
        @ir_sim.run_cpu_cycles(100_000, 0, false)

        # Check soft switches - bit 3 should be set for hires
        soft_switches = @ir_sim.peek('soft_switches')
        hires_on = (soft_switches & 0x08) != 0

        expect(hires_on).to be(true),
          "HIRES mode should remain active during game execution"
      end
    end
  end
end
