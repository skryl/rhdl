# frozen_string_literal: true

module RHDL
  module Examples
    module AO486
      # Minimal FAT12 floppy image reader for MS-DOS boot testing.
      # Supports 1.44MB (3.5" HD) and 360KB (5.25" DD) floppy images.
      class FAT12
        SECTOR_SIZE = 512

        attr_reader :bytes, :bpb

        def initialize(image_path_or_bytes)
          @bytes = if image_path_or_bytes.is_a?(String) && File.exist?(image_path_or_bytes)
                     File.binread(image_path_or_bytes).bytes
                   elsif image_path_or_bytes.is_a?(String)
                     image_path_or_bytes.bytes
                   else
                     image_path_or_bytes.to_a
                   end
          parse_bpb
        end

        # Returns the 512-byte boot sector as an array of bytes.
        def boot_sector
          @bytes[0, SECTOR_SIZE]
        end

        # Returns true if the boot sector has a valid signature (0x55AA at offset 510).
        def valid_boot_signature?
          @bytes[510] == 0x55 && @bytes[511] == 0xAA
        end

        # Lists root directory entries as an array of hashes.
        def root_directory
          entries = []
          root_start = root_dir_offset
          (0...@bpb[:root_entries]).each do |i|
            offset = root_start + i * 32
            first_byte = @bytes[offset]
            break if first_byte == 0x00  # end of directory
            next if first_byte == 0xE5   # deleted entry

            attrs = @bytes[offset + 11]
            next if attrs == 0x0F  # long filename entry

            name = @bytes[offset, 8].pack('C*').rstrip
            ext = @bytes[offset + 8, 3].pack('C*').rstrip
            filename = ext.empty? ? name : "#{name}.#{ext}"

            cluster = read16(offset + 26)
            size = read32(offset + 28)

            entries << {
              name: filename,
              attrs: attrs,
              cluster: cluster,
              size: size,
              volume_label: (attrs & 0x08) != 0,
              directory: (attrs & 0x10) != 0,
              system: (attrs & 0x04) != 0,
              hidden: (attrs & 0x02) != 0,
              read_only: (attrs & 0x01) != 0
            }
          end
          entries
        end

        # Reads a file from the floppy by name (e.g., "IO.SYS").
        def read_file(filename)
          entry = root_directory.find { |e| e[:name].upcase == filename.upcase }
          return nil unless entry

          read_cluster_chain(entry[:cluster], entry[:size])
        end

        # Reads sectors from the floppy image (CHS or LBA).
        # Returns an array of bytes.
        def read_sectors_lba(lba, count)
          offset = lba * SECTOR_SIZE
          length = count * SECTOR_SIZE
          @bytes[offset, length] || []
        end

        # Converts CHS to LBA for this floppy geometry.
        def chs_to_lba(cylinder, head, sector)
          (cylinder * @bpb[:heads] + head) * @bpb[:sectors_per_track] + (sector - 1)
        end

        # Reads sectors by CHS address.
        def read_sectors_chs(cylinder, head, sector, count)
          lba = chs_to_lba(cylinder, head, sector)
          read_sectors_lba(lba, count)
        end

        private

        def parse_bpb
          @bpb = {
            bytes_per_sector: read16(11),
            sectors_per_cluster: @bytes[13],
            reserved_sectors: read16(14),
            num_fats: @bytes[16],
            root_entries: read16(17),
            total_sectors: read16(19),
            media_descriptor: @bytes[21],
            sectors_per_fat: read16(22),
            sectors_per_track: read16(24),
            heads: read16(26),
            hidden_sectors: read32(28)
          }
        end

        def root_dir_offset
          (@bpb[:reserved_sectors] + @bpb[:num_fats] * @bpb[:sectors_per_fat]) * SECTOR_SIZE
        end

        def data_area_offset
          root_dir_offset + @bpb[:root_entries] * 32
        end

        def cluster_to_offset(cluster)
          data_area_offset + (cluster - 2) * @bpb[:sectors_per_cluster] * SECTOR_SIZE
        end

        def read_fat_entry(cluster)
          fat_offset = @bpb[:reserved_sectors] * SECTOR_SIZE
          byte_offset = fat_offset + (cluster * 3 / 2)

          if cluster.even?
            ((@bytes[byte_offset + 1] & 0x0F) << 8) | @bytes[byte_offset]
          else
            ((@bytes[byte_offset + 1]) << 4) | ((@bytes[byte_offset] >> 4) & 0x0F)
          end
        end

        def read_cluster_chain(start_cluster, size)
          result = []
          cluster = start_cluster
          remaining = size
          cluster_size = @bpb[:sectors_per_cluster] * SECTOR_SIZE

          while remaining > 0 && cluster >= 2 && cluster < 0xFF8
            offset = cluster_to_offset(cluster)
            chunk = [remaining, cluster_size].min
            result.concat(@bytes[offset, chunk])
            remaining -= chunk
            cluster = read_fat_entry(cluster)
          end

          result
        end

        def read16(offset)
          @bytes[offset] | (@bytes[offset + 1] << 8)
        end

        def read32(offset)
          @bytes[offset] | (@bytes[offset + 1] << 8) |
            (@bytes[offset + 2] << 16) | (@bytes[offset + 3] << 24)
        end
      end
    end
  end
end
