# frozen_string_literal: true

# Apple II DiskII HDL with actual .dsk files
#
# This test verifies the Disk II controller HDL works with real disk images.
# Uses the IR compiler with Apple II mode for fast simulation.

require 'rhdl'
require_relative '../../../examples/apple2/hdl/apple2'
require 'rhdl/codegen'
require 'rhdl/codegen/ir/sim/ir_compiler'

RSpec.describe 'Apple2 DiskII HDL with actual .dsk files', :slow do
  # Paths to required disk images and ROMs
  DISK_DIR = File.join(__dir__, '../../../examples/apple2/software/disks')
  ROM_DIR = File.join(__dir__, '../../../examples/apple2/software/roms')
  KARATEKA_PATH = File.join(DISK_DIR, 'karateka.dsk')
  APPLEIIGO_ROM_PATH = File.join(ROM_DIR, 'appleiigo.rom')
  DISK_II_BOOT_ROM_PATH = File.join(ROM_DIR, 'disk2_boot.bin')

  # Check if test resources are available
  KARATEKA_AVAILABLE = File.exist?(KARATEKA_PATH)
  ROM_AVAILABLE = File.exist?(APPLEIIGO_ROM_PATH)
  BOOT_ROM_AVAILABLE = File.exist?(DISK_II_BOOT_ROM_PATH)
  IR_COMPILER_AVAILABLE = RHDL::Codegen::IR::COMPILER_AVAILABLE

  describe 'IR Compiler boot with karateka from disk', if: (KARATEKA_AVAILABLE && ROM_AVAILABLE && IR_COMPILER_AVAILABLE) do
    before(:all) do
      # Load ROM and disk data
      @rom_data = File.binread(APPLEIIGO_ROM_PATH).bytes
      @boot_rom_data = BOOT_ROM_AVAILABLE ? File.binread(DISK_II_BOOT_ROM_PATH).bytes : nil

      # Load Karateka disk and convert to nibble format
      disk_data = File.binread(KARATEKA_PATH).bytes
      @disk_tracks = convert_dsk_to_nibbles(disk_data)

      # Generate IR JSON for Apple II
      ir = RHDL::Apple2::Apple2.to_flat_ir
      @ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)
    end

    # Convert DSK format to nibble format (simplified)
    def convert_dsk_to_nibbles(dsk_data)
      tracks = []
      35.times do |track|
        track_offset = track * 16 * 256
        nibbles = []

        16.times do |sector|
          # DOS 3.3 interleave
          physical_sector = [0x00, 0x07, 0x0E, 0x06, 0x0D, 0x05, 0x0C, 0x04,
                            0x0B, 0x03, 0x0A, 0x02, 0x09, 0x01, 0x08, 0x0F][sector]
          sector_data = dsk_data[track_offset + physical_sector * 256, 256] || Array.new(256, 0)

          # Sync bytes
          48.times { nibbles << 0xFF }

          # Address field
          nibbles.concat([0xD5, 0xAA, 0x96])  # Prologue
          nibbles.concat(encode_4_and_4(0xFE))  # Volume
          nibbles.concat(encode_4_and_4(track))
          nibbles.concat(encode_4_and_4(sector))
          nibbles.concat(encode_4_and_4(0xFE ^ track ^ sector))  # Checksum
          nibbles.concat([0xDE, 0xAA, 0xEB])  # Epilogue

          # Gap
          6.times { nibbles << 0xFF }

          # Data field
          nibbles.concat([0xD5, 0xAA, 0xAD])  # Prologue
          nibbles.concat(encode_6_and_2(sector_data))
          nibbles.concat([0xDE, 0xAA, 0xEB])  # Epilogue
        end

        # Pad to track size
        while nibbles.length < 6656
          nibbles << 0xFF
        end
        tracks << nibbles[0, 6656]
      end
      tracks
    end

    def encode_4_and_4(value)
      [(value >> 1) | 0xAA, value | 0xAA]
    end

    def encode_6_and_2(sector_data)
      # Simplified 6-and-2 encoding
      translate = [0x96, 0x97, 0x9A, 0x9B, 0x9D, 0x9E, 0x9F, 0xA6,
                   0xA7, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF, 0xB2, 0xB3,
                   0xB4, 0xB5, 0xB6, 0xB7, 0xB9, 0xBA, 0xBB, 0xBC,
                   0xBD, 0xBE, 0xBF, 0xCB, 0xCD, 0xCE, 0xCF, 0xD3,
                   0xD6, 0xD7, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE,
                   0xDF, 0xE5, 0xE6, 0xE7, 0xE9, 0xEA, 0xEB, 0xEC,
                   0xED, 0xEE, 0xEF, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6,
                   0xF7, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF]

      # Build auxiliary buffer (86 bytes of 2-bit values)
      aux = Array.new(86, 0)
      86.times do |i|
        val = 0
        val |= ((sector_data[i] & 0x01) << 1) | ((sector_data[i] & 0x02) >> 1) if i < 256
        val |= ((sector_data[i + 86] & 0x01) << 3) | ((sector_data[i + 86] & 0x02) << 1) if i + 86 < 256
        val |= ((sector_data[i + 172] & 0x01) << 5) | ((sector_data[i + 172] & 0x02) << 3) if i + 172 < 256
        aux[i] = val & 0x3F
      end

      # Build main data (256 bytes)
      main = sector_data.map { |b| (b >> 2) & 0x3F }

      # Combine and translate
      combined = aux + main
      result = []
      checksum = 0
      combined.each do |val|
        result << translate[val ^ checksum]
        checksum = val
      end
      result << translate[checksum]  # Final checksum

      result
    end

    describe 'basic disk boot' do
      before(:each) do
        # Skip this test - the IR compiler's Apple II extension doesn't support disk I/O yet.
        # The extension only handles RAM/ROM, not the disk controller's track memory.
        # This test requires:
        # 1. Boot ROM at $C600-$C6FF to be accessible (currently returns 0 for I/O space)
        # 2. Disk I/O registers at $C0E0-$C0EF to work
        # 3. Track data to be loadable into the disk controller's memory
        skip 'IR compiler Apple II extension does not support disk I/O yet'

        skip 'Boot ROM not available' unless BOOT_ROM_AVAILABLE

        @ir_sim = RHDL::Codegen::IR::IrCompilerWrapper.new(@ir_json, sub_cycles: 14)

        # Patch reset vector to $C600 (disk boot)
        patched_rom = @rom_data.dup
        patched_rom[0x2FFC] = 0x00  # $C600 low byte
        patched_rom[0x2FFD] = 0xC6  # $C600 high byte

        @ir_sim.load_rom(patched_rom)
        @ir_sim.reset

        # Track loading state
        @loaded_track = 0
        @track_data_loaded = false
      end

      def load_track(track_num)
        return unless @disk_tracks && @disk_tracks[track_num]

        track_data = @disk_tracks[track_num]
        # Load track into RAM at a specific location the disk controller will read from
        # This is a simplified approach - real disk I/O is complex
        @loaded_track = track_num
        @track_data_loaded = true
      end

      def check_and_load_track(sim)
        begin
          # Check current track from stepper phases
          phases = []
          4.times do |i|
            phase = sim.peek("disk__phase#{i}") rescue 0
            phases << phase
          end

          # Calculate track from phases (simplified)
          new_track = (phases[0].to_i | (phases[1].to_i << 1) | (phases[2].to_i << 2) | (phases[3].to_i << 3)) / 2

          if new_track != @loaded_track && new_track >= 0 && new_track < 35
            load_track(new_track)
            return true
          end
        rescue
          # Signals not available
        end
        false
      end

      it 'boots from disk and transfers to game code' do
        total_cycles = 0
        max_cycles = 5_000_000

        puts "\n=== Disk Boot Test ==="

        # Run until PC is in game code region or max cycles
        game_code_count = 0
        while total_cycles < max_cycles
          @ir_sim.run_cpu_cycles(100_000, 0, false)
          total_cycles += 100_000

          check_and_load_track(@ir_sim)

          pc = @ir_sim.peek('cpu__pc_reg')

          # Track time in game code region ($6000-$BFFF)
          if pc >= 0x6000 && pc <= 0xBFFF
            game_code_count += 1
            # Game code running consistently = boot complete
            if game_code_count >= 5
              puts "Boot complete at #{total_cycles / 1_000_000}M cycles, PC=$#{format('%04X', pc)}"
              break
            end
          else
            game_code_count = 0
          end

          # Progress indicator
          if total_cycles % 1_000_000 == 0
            puts "  #{total_cycles / 1_000_000}M cycles: PC=$#{format('%04X', pc)}"
          end
        end

        final_pc = @ir_sim.peek('cpu__pc_reg')
        puts "Final PC: $#{format('%04X', final_pc)}"

        # Assertions
        expect(final_pc).to be_between(0x6000, 0xBFFF),
          "Expected PC in game code region ($6000-$BFFF), got $#{format('%04X', final_pc)}"
      end
    end
  end
end
