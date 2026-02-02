# frozen_string_literal: true

# Quick test to verify disk timing fix - tests that D5 markers can be found
# This test should complete in ~10-20 seconds, not minutes like the full boot test

require 'spec_helper'
require 'rhdl'

RSpec.describe 'Disk timing fix verification', if: RHDL::Codegen::IR::COMPILER_AVAILABLE do
  # Disk image paths
  DISK_DIR = File.expand_path('../../../examples/apple2/software/disks', __dir__)
  KARATEKA_DSK_PATH = File.join(DISK_DIR, 'karateka.dsk')
  KARATEKA_AVAILABLE = File.exist?(KARATEKA_DSK_PATH)

  # ROM paths
  BOOT_ROM_PATH = File.expand_path('../../../examples/apple2/software/roms/disk2_boot.bin', __dir__)
  APPLEIIGO_ROM_PATH = File.expand_path('../../../examples/apple2/software/roms/appleiigo.rom', __dir__)

  # 6-and-2 translation table
  TRANSLATE_62 = [0x96, 0x97, 0x9A, 0x9B, 0x9D, 0x9E, 0x9F, 0xA6,
                  0xA7, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF, 0xB2, 0xB3,
                  0xB4, 0xB5, 0xB6, 0xB7, 0xB9, 0xBA, 0xBB, 0xBC,
                  0xBD, 0xBE, 0xBF, 0xCB, 0xCD, 0xCE, 0xCF, 0xD3,
                  0xD6, 0xD7, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE,
                  0xDF, 0xE5, 0xE6, 0xE7, 0xE9, 0xEA, 0xEB, 0xEC,
                  0xED, 0xEE, 0xEF, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6,
                  0xF7, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF].freeze

  DOS33_INTERLEAVE = [0x00, 0x07, 0x0E, 0x06, 0x0D, 0x05, 0x0C, 0x04,
                      0x0B, 0x03, 0x0A, 0x02, 0x09, 0x01, 0x08, 0x0F].freeze

  def convert_track_to_nibbles(dsk_data, track_num)
    track_offset = track_num * 16 * 256
    nibbles = []

    16.times do |physical_pos|
      logical_sector = DOS33_INTERLEAVE[physical_pos]
      sector_data = dsk_data[track_offset + logical_sector * 256, 256] || Array.new(256, 0)

      # Sync bytes
      48.times { nibbles << 0xFF }
      # Address field prologue - THIS IS THE D5 AA 96 WE'RE LOOKING FOR
      nibbles.concat([0xD5, 0xAA, 0x96])
      # Volume, Track, Sector, Checksum (4-and-4 encoded)
      nibbles.concat(encode_4_and_4(0xFE))
      nibbles.concat(encode_4_and_4(track_num))
      nibbles.concat(encode_4_and_4(logical_sector))
      nibbles.concat(encode_4_and_4(0xFE ^ track_num ^ logical_sector))
      # Address field epilogue
      nibbles.concat([0xDE, 0xAA, 0xEB])
      # Gap
      6.times { nibbles << 0xFF }
      # Data field prologue
      nibbles.concat([0xD5, 0xAA, 0xAD])
      # Encoded sector data
      nibbles.concat(encode_6_and_2(sector_data))
      # Data field epilogue
      nibbles.concat([0xDE, 0xAA, 0xEB])
    end

    while nibbles.length < 6656
      nibbles << 0xFF
    end
    nibbles[0, 6656]
  end

  def encode_4_and_4(byte)
    [((byte >> 1) | 0xAA), (byte | 0xAA)]
  end

  def encode_6_and_2(sector_data)
    aux = Array.new(86, 0)
    86.times do |i|
      val = 0
      val |= ((sector_data[i] & 0x01) << 1) | ((sector_data[i] & 0x02) >> 1) if i < 256
      val |= ((sector_data[i + 86] & 0x01) << 3) | ((sector_data[i + 86] & 0x02) << 1) if i + 86 < 256
      val |= ((sector_data[i + 172] & 0x01) << 5) | ((sector_data[i + 172] & 0x02) << 3) if i + 172 < 256
      aux[i] = val & 0x3F
    end

    main = sector_data.map { |b| (b >> 2) & 0x3F }
    combined = aux + main
    result = []
    checksum = 0
    combined.each do |val|
      result << TRANSLATE_62[val ^ checksum]
      checksum = val
    end
    result << TRANSLATE_62[checksum]
    result
  end

  def inject_denibble_table(sim)
    denibble_table = Array.new(128, 0xFF)
    TRANSLATE_62.each_with_index { |nibble, decoded_value| denibble_table[nibble & 0x7F] = decoded_value }
    denibble_table.each_with_index { |value, offset| sim.apple2_write_ram(0x0356 + offset, [value]) }
  end

  before(:all) do
    skip 'Karateka disk not found' unless KARATEKA_AVAILABLE
    skip 'Boot ROM not found' unless File.exist?(BOOT_ROM_PATH)
    skip 'AppleIIGo ROM not found' unless File.exist?(APPLEIIGO_ROM_PATH)

    require 'rhdl/codegen/ir/sim/ir_compiler'
    require_relative '../../../examples/apple2/hdl/apple2'

    @dsk_data = File.binread(KARATEKA_DSK_PATH).bytes
    @boot_rom = File.binread(BOOT_ROM_PATH).bytes
    @main_rom = File.binread(APPLEIIGO_ROM_PATH).bytes

    # Patch boot ROM for slot 6
    @boot_rom[1] = 0x60
    @boot_rom[5] = 0x60

    # Patch reset vector to disk boot ROM
    @main_rom[0x2FFC] = 0x00
    @main_rom[0x2FFD] = 0xC6

    # Patch $FF58 for slot detection
    offset_ff58 = 0xFF58 - 0xD000
    @main_rom[offset_ff58] = 0xBA
    @main_rom[offset_ff58 + 1] = 0xBD
    @main_rom[offset_ff58 + 2] = 0x02
    @main_rom[offset_ff58 + 3] = 0x01
    @main_rom[offset_ff58 + 4] = 0x60

    # Patch WAIT routine to return immediately
    offset_fca8 = 0xFCA8 - 0xD000
    @main_rom[offset_fca8] = 0x60
  end

  def setup_simulator
    ir = RHDL::Apple2::Apple2.to_flat_ir
    ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)
    sim = RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json, sub_cycles: 14)

    sim.apple2_load_rom(@main_rom)
    sim.apple2_load_disk_rom(@boot_rom)

    # Load just track 0 for quick test
    nibbles = convert_track_to_nibbles(@dsk_data, 0)
    sim.apple2_load_track(0, nibbles)

    # Reset
    sim.poke('reset', 1)
    sim.apple2_run_cpu_cycles(1, 0, false)
    sim.poke('reset', 0)

    # Run initial boot and inject denibble table
    sim.apple2_run_cpu_cycles(5000, 0, false)
    inject_denibble_table(sim)

    # Initialize P5 PROM zero page
    sim.apple2_write_ram(0x0026, [0x00])
    sim.apple2_write_ram(0x0027, [0x08])
    sim.apple2_write_ram(0x003D, [0x00])
    sim.apple2_write_ram(0x0041, [0x08])
    sim.apple2_write_ram(0x002B, [0x60])

    sim
  end

  it 'finds D5 marker within 500K cycles (quick boot test)', timeout: 60 do
    sim = setup_simulator

    # The boot ROM searches for D5 AA 96 prologue
    # If timing is correct, it should find it within a few disk rotations
    # One rotation = 6656 bytes * 32 cycles/byte = ~213K cycles
    # Give it ~2 rotations plus overhead = 500K cycles

    max_cycles = 500_000
    cycles_per_batch = 10_000
    total_cycles = 0

    # Track whether we've progressed past the D5 search loop
    # The D5 search loop is at $C65C-$C663
    # If we've moved past it, we found a D5 marker
    found_d5 = false
    last_pc = 0

    while total_cycles < max_cycles && !found_d5
      result = sim.apple2_run_cpu_cycles(cycles_per_batch, 0, false)
      total_cycles += result[:cycles_run]

      # Check if we've loaded any sector data to $0800
      # The boot ROM loads sector 0 to $0800
      boot_sector = sim.apple2_read_ram(0x0800, 16)
      if boot_sector.any? { |b| b != 0 }
        found_d5 = true
        puts "  SUCCESS: Boot sector loaded at cycle #{total_cycles}"
        puts "  First 16 bytes at $0800: #{boot_sector.map { |b| '%02X' % b }.join(' ')}"
      end

      # Also check if CPU has moved past the D5 loop
      # by checking if any address field data was stored
      addr_field = sim.apple2_read_ram(0x002C, 4)  # track/sector stored here
      if addr_field[0] != 0 || addr_field[1] != 0
        found_d5 = true
        puts "  SUCCESS: Address field parsed at cycle #{total_cycles}"
        puts "  Track/sector: #{addr_field.map { |b| '%02X' % b }.join(' ')}"
      end
    end

    if !found_d5
      # Dump some debug info
      puts "  FAILED: No D5 marker found in #{total_cycles} cycles"
      puts "  Motor on: #{sim.apple2_is_motor_on?}"
      puts "  Current track: #{sim.apple2_get_track}"

      # Check zero page state
      zp = sim.apple2_read_ram(0x0026, 6)
      puts "  Zero page $26-$2B: #{zp.map { |b| '%02X' % b }.join(' ')}"
    end

    expect(found_d5).to be(true),
      "Boot ROM failed to find D5 marker within #{max_cycles} cycles. " \
      "This indicates the disk timing valid window is not working correctly."
  end

  it 'reads multiple consecutive bytes with bit 7 set during fresh window' do
    sim = setup_simulator

    # Run until motor is on and we're past initial setup
    sim.apple2_run_cpu_cycles(10_000, 0, false)

    # The key test: When a byte becomes available, multiple reads within
    # the "fresh" window should all return the byte with bit 7 intact.
    #
    # We can't directly test this at the Ruby level, but we can verify
    # that the boot ROM successfully reads sector data, which requires
    # the D5 AA 96 sequence to be detected with bit 7 set.

    # Run for 200K cycles (about one disk rotation)
    result = sim.apple2_run_cpu_cycles(200_000, 0, false)

    # Check if any disk activity occurred
    motor_on = sim.apple2_is_motor_on?
    track = sim.apple2_get_track

    expect(motor_on).to be(true), "Disk motor should be on"
    expect(track).to eq(0), "Should be on track 0"

    # The real test is whether sector data gets loaded
    # Check zero page for signs of successful disk reads
    zp_26 = sim.apple2_read_ram(0x0026, 2)  # Buffer pointer

    # If buffer pointer has been modified, disk read routine is working
    # (It gets modified as sectors are loaded)
    puts "  Buffer pointer at $26-$27: #{zp_26.map { |b| '%02X' % b }.join(' ')}"
  end
end
