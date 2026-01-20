# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for converting disk images to binary files
      class DiskConvertTask < Task
        # DOS 3.3 disk constants
        TRACKS = 35
        SECTORS_PER_TRACK = 16
        BYTES_PER_SECTOR = 256
        TRACK_SIZE = SECTORS_PER_TRACK * BYTES_PER_SECTOR  # 4096 bytes
        DISK_SIZE = TRACKS * TRACK_SIZE                     # 143360 bytes

        # DOS 3.3 sector interleaving table (physical to logical)
        DOS33_INTERLEAVE = [
          0x00, 0x07, 0x0E, 0x06, 0x0D, 0x05, 0x0C, 0x04,
          0x0B, 0x03, 0x0A, 0x02, 0x09, 0x01, 0x08, 0x0F
        ].freeze

        # ProDOS sector interleaving (physical to logical)
        PRODOS_INTERLEAVE = [
          0x00, 0x08, 0x01, 0x09, 0x02, 0x0A, 0x03, 0x0B,
          0x04, 0x0C, 0x05, 0x0D, 0x06, 0x0E, 0x07, 0x0F
        ].freeze

        def run
          if options[:info]
            show_disk_info
          elsif options[:extract_boot]
            extract_boot_sector
          elsif options[:extract_tracks]
            extract_tracks
          elsif options[:convert]
            convert_disk_to_binary
          else
            convert_disk_to_binary
          end
        end

        # Convert entire disk to a flat binary image for direct memory loading
        # This reorders sectors from DOS 3.3 logical order to sequential order
        def convert_disk_to_binary
          input_file = options[:input] || options[:disk]
          raise "No input disk file specified" unless input_file
          raise "Disk file not found: #{input_file}" unless File.exist?(input_file)

          bytes = File.binread(input_file).bytes
          raise "Invalid disk image size: #{bytes.length} (expected #{DISK_SIZE})" unless bytes.length == DISK_SIZE

          output_file = options[:output] || input_file.sub(/\.dsk$/i, '.bin')
          base_addr = options[:base_addr] || 0x0800
          end_addr = options[:end_addr] || 0xBFFF

          puts_header "Converting disk to binary"
          puts "Input:  #{input_file}"
          puts "Output: #{output_file}"
          puts "Base address: $#{base_addr.to_s(16).upcase}"
          puts "End address:  $#{end_addr.to_s(16).upcase}"
          puts

          # Create output buffer
          mem_size = end_addr - base_addr + 1
          output = Array.new(mem_size, 0)

          # Determine which tracks/sectors to extract
          start_track = options[:start_track] || 0
          end_track = options[:end_track] || TRACKS - 1
          interleave = options[:prodos] ? PRODOS_INTERLEAVE : DOS33_INTERLEAVE

          # Read sectors in physical order and write sequentially
          offset = 0
          (start_track..end_track).each do |track|
            SECTORS_PER_TRACK.times do |phys_sector|
              break if offset >= mem_size

              # Map physical sector to logical sector
              log_sector = interleave[phys_sector]

              # Read sector data from disk image
              disk_offset = (track * TRACK_SIZE) + (log_sector * BYTES_PER_SECTOR)
              sector_data = bytes[disk_offset, BYTES_PER_SECTOR]

              # Copy to output buffer
              bytes_to_copy = [BYTES_PER_SECTOR, mem_size - offset].min
              sector_data[0, bytes_to_copy].each_with_index do |b, i|
                output[offset + i] = b
              end
              offset += BYTES_PER_SECTOR
            end
          end

          # Write binary file
          File.binwrite(output_file, output.pack('C*'))
          puts "Wrote #{output.length} bytes to #{output_file}"
          puts
          puts "To load this binary:"
          puts "  bin/apple2 -a #{base_addr.to_s(16)} #{output_file}"
        end

        # Extract just the boot sector (track 0, sector 0)
        def extract_boot_sector
          input_file = options[:input] || options[:disk]
          raise "No input disk file specified" unless input_file
          raise "Disk file not found: #{input_file}" unless File.exist?(input_file)

          bytes = File.binread(input_file).bytes
          raise "Invalid disk image size: #{bytes.length}" unless bytes.length == DISK_SIZE

          output_file = options[:output] || input_file.sub(/\.dsk$/i, '_boot.bin')

          puts_header "Extracting boot sector"
          puts "Input:  #{input_file}"
          puts "Output: #{output_file}"
          puts

          # Boot sector is track 0, sector 0 (logical), which is physical sector 0 in DOS 3.3
          boot_sector = bytes[0, BYTES_PER_SECTOR]

          File.binwrite(output_file, boot_sector.pack('C*'))
          puts "Wrote #{boot_sector.length} bytes to #{output_file}"

          # Show disassembly preview
          puts
          puts "First 16 bytes:"
          boot_sector[0, 16].each_slice(8) do |row|
            hex = row.map { |b| format('%02X', b) }.join(' ')
            ascii = row.map { |b| b >= 0x20 && b < 0x7F ? b.chr : '.' }.join
            puts "  #{hex}  #{ascii}"
          end
        end

        # Extract specific tracks to binary
        def extract_tracks
          input_file = options[:input] || options[:disk]
          raise "No input disk file specified" unless input_file
          raise "Disk file not found: #{input_file}" unless File.exist?(input_file)

          bytes = File.binread(input_file).bytes
          raise "Invalid disk image size: #{bytes.length}" unless bytes.length == DISK_SIZE

          start_track = options[:start_track] || 0
          end_track = options[:end_track] || 2
          output_file = options[:output] || input_file.sub(/\.dsk$/i, "_t#{start_track}-#{end_track}.bin")
          interleave = options[:prodos] ? PRODOS_INTERLEAVE : DOS33_INTERLEAVE

          puts_header "Extracting tracks #{start_track}-#{end_track}"
          puts "Input:  #{input_file}"
          puts "Output: #{output_file}"
          puts

          output = []
          (start_track..end_track).each do |track|
            SECTORS_PER_TRACK.times do |phys_sector|
              log_sector = interleave[phys_sector]
              disk_offset = (track * TRACK_SIZE) + (log_sector * BYTES_PER_SECTOR)
              output.concat(bytes[disk_offset, BYTES_PER_SECTOR])
            end
          end

          File.binwrite(output_file, output.pack('C*'))
          puts "Wrote #{output.length} bytes (#{end_track - start_track + 1} tracks) to #{output_file}"
        end

        # Show information about a disk image
        def show_disk_info
          input_file = options[:input] || options[:disk]
          raise "No input disk file specified" unless input_file
          raise "Disk file not found: #{input_file}" unless File.exist?(input_file)

          bytes = File.binread(input_file).bytes

          puts_header "Disk Image Information"
          puts "File: #{input_file}"
          puts "Size: #{bytes.length} bytes"
          puts

          if bytes.length == DISK_SIZE
            puts "Format: DOS 3.3 / ProDOS compatible (35 tracks, 16 sectors)"
            puts "Tracks: #{TRACKS}"
            puts "Sectors per track: #{SECTORS_PER_TRACK}"
            puts "Bytes per sector: #{BYTES_PER_SECTOR}"
            puts

            # Analyze boot sector
            boot = bytes[0, BYTES_PER_SECTOR]
            puts "Boot sector analysis:"
            puts "  First byte: $#{format('%02X', boot[0])}"

            # Check for DOS 3.3 boot signature
            if boot[0] == 0x01
              puts "  Detected: DOS 3.3 disk"
            elsif boot[0] == 0x4C
              puts "  Detected: JMP instruction (custom boot loader)"
              jmp_addr = boot[1] | (boot[2] << 8)
              puts "  Jump address: $#{format('%04X', jmp_addr)}"
            end

            # Show volume info if present (VTOC at track 17, sector 0)
            vtoc_offset = 17 * TRACK_SIZE  # Track 17, sector 0 (logical = physical for sector 0)
            vtoc = bytes[vtoc_offset, BYTES_PER_SECTOR]

            if vtoc[1] == 17 && vtoc[2] == 15  # Standard VTOC location pointers
              puts
              puts "VTOC (Volume Table of Contents) found at track 17:"
              puts "  DOS version: #{vtoc[3]}"
              puts "  Volume number: #{vtoc[6]}"
              puts "  Tracks per disk: #{vtoc[0x34]}"
              puts "  Sectors per track: #{vtoc[0x35]}"
            end
          else
            puts "Warning: Non-standard disk size"
            puts "Expected #{DISK_SIZE} bytes for DOS 3.3 format"
          end
        end
      end
    end
  end
end
