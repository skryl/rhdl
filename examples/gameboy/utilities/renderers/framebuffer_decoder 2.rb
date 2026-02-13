# frozen_string_literal: true

module RHDL
  module Examples
    module GameBoy
      module FramebufferDecoder
        SCREEN_WIDTH = 160
        SCREEN_HEIGHT = 144
        VRAM_SIZE = 8192
        OAM_SIZE = 160

        module_function

        # Reconstruct a DMG frame from VRAM/OAM/register state.
        # Returns a flat 160*144 array with 2-bit DMG palette indices (0..3).
        def decode_dmg_flat(vram:, oam:, lcdc:, scx:, scy:, bgp:, obp0:, obp1:, wx:, wy:)
          fb = Array.new(SCREEN_WIDTH * SCREEN_HEIGHT, 0)
          bg_raw = Array.new(SCREEN_WIDTH * SCREEN_HEIGHT, 0)

          return fb if (lcdc & 0x80).zero?

          bg_enable = (lcdc & 0x01) != 0
          sprite_enable = (lcdc & 0x02) != 0
          sprite_height = (lcdc & 0x04) != 0 ? 16 : 8
          win_enable = (lcdc & 0x20) != 0
          unsigned_tiles = (lcdc & 0x10) != 0
          bg_map_base = (lcdc & 0x08) != 0 ? 0x1C00 : 0x1800
          win_map_base = (lcdc & 0x40) != 0 ? 0x1C00 : 0x1800
          win_x_start = wx - 7

          SCREEN_HEIGHT.times do |y|
            win_line_active = win_enable && y >= wy && win_x_start < SCREEN_WIDTH
            SCREEN_WIDTH.times do |x|
              idx = (y * SCREEN_WIDTH) + x
              raw = 0
              color = 0

              if bg_enable
                use_window = win_line_active && (x >= win_x_start)
                map_base = use_window ? win_map_base : bg_map_base
                src_x = use_window ? ((x - win_x_start) & 0xFF) : ((x + scx) & 0xFF)
                src_y = use_window ? ((y - wy) & 0xFF) : ((y + scy) & 0xFF)

                tile_row = (src_y >> 3) & 0x1F
                tile_col = (src_x >> 3) & 0x1F
                map_addr = (map_base + (tile_row * 32) + tile_col) & 0x1FFF
                tile_num = vram_byte(vram, map_addr)
                row_in_tile = src_y & 0x07

                tile_addr =
                  if unsigned_tiles
                    ((tile_num << 4) + (row_in_tile << 1)) & 0x1FFF
                  else
                    signed_tile = tile_num < 0x80 ? tile_num : (tile_num - 0x100)
                    (0x1000 + (signed_tile * 16) + (row_in_tile << 1)) & 0x1FFF
                  end

                lo = vram_byte(vram, tile_addr)
                hi = vram_byte(vram, (tile_addr + 1) & 0x1FFF)
                bit = 7 - (src_x & 0x07)
                raw = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1)
                color = (bgp >> (raw * 2)) & 0x03
              end

              bg_raw[idx] = raw
              fb[idx] = color
            end
          end

          return fb unless sprite_enable

          SCREEN_HEIGHT.times do |y|
            line = []

            40.times do |i|
              base = i * 4
              sy = oam_byte(oam, base) - 16
              sx = oam_byte(oam, base + 1) - 8
              next if y < sy || y >= (sy + sprite_height)
              next if sx <= -8 || sx >= SCREEN_WIDTH

              line << [i, sx, sy, oam_byte(oam, base + 2), oam_byte(oam, base + 3)]
            end

            line.sort_by! { |entry| [entry[1], entry[0]] }
            line = line.first(10)

            line.reverse_each do |(_idx, sx, sy, tile, attr)|
              row = y - sy
              y_flip = (attr & 0x40) != 0
              x_flip = (attr & 0x20) != 0
              behind_bg = (attr & 0x80) != 0
              row = (sprite_height - 1 - row) if y_flip

              tile_index = tile
              if sprite_height == 16
                tile_index &= 0xFE
                tile_index += 1 if row >= 8
              end

              row_in_tile = row & 0x07
              tile_addr = ((tile_index << 4) + (row_in_tile << 1)) & 0x1FFF
              lo = vram_byte(vram, tile_addr)
              hi = vram_byte(vram, (tile_addr + 1) & 0x1FFF)
              palette = (attr & 0x10) != 0 ? obp1 : obp0

              8.times do |col|
                x = sx + col
                next if x < 0 || x >= SCREEN_WIDTH

                bit = x_flip ? col : (7 - col)
                raw = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1)
                next if raw.zero?

                fb_idx = (y * SCREEN_WIDTH) + x
                next if behind_bg && !bg_raw[fb_idx].zero?

                fb[fb_idx] = (palette >> (raw * 2)) & 0x03
              end
            end
          end

          fb
        end

        def flat_to_rows(flat)
          Array.new(SCREEN_HEIGHT) do |y|
            start = y * SCREEN_WIDTH
            flat[start, SCREEN_WIDTH]
          end
        end

        def vram_byte(vram, addr)
          i = addr & 0x1FFF
          i < VRAM_SIZE ? (vram[i] || 0) : 0
        end
        private_class_method :vram_byte

        def oam_byte(oam, addr)
          i = addr & 0xFF
          i < OAM_SIZE ? (oam[i] || 0) : 0
        end
        private_class_method :oam_byte
      end
    end
  end
end
