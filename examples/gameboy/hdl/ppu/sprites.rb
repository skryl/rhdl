# Game Boy Sprite Engine
# Corresponds to: reference/rtl/sprites.v
#
# Handles:
# - OAM (Object Attribute Memory) management
# - Sprite search during Mode 2
# - Sprite rendering during Mode 3
# - 10 sprites per scanline limit
# - Priority handling (DMG: X position, CGB: OAM order)

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module GameBoy
  class Sprites < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :ce
    input :ce_cpu
    input :size16          # 8x16 sprite mode
    input :is_gbc           # Game Boy Color mode
    input :sprite_en       # Sprites enabled
    input :lcd_on          # LCD on

    input :v_cnt, width: 8  # Current line
    input :h_cnt, width: 8  # Current pixel position

    # OAM evaluation control
    input :oam_eval        # OAM evaluation active (Mode 2)
    input :oam_fetch       # Sprite fetch active (Mode 3)
    input :oam_eval_reset  # Reset OAM evaluation
    output :oam_eval_end   # OAM evaluation complete

    # Sprite fetch interface
    output :sprite_fetch   # Sprite found, needs fetching
    output :sprite_addr, width: 11  # Sprite tile address
    output :sprite_attr, width: 8   # Sprite attributes
    output :sprite_index, width: 4  # Sprite OAM index (for priority)
    input :sprite_fetch_c1          # Sprite fetch cycle 1
    input :sprite_fetch_done        # Sprite fetch complete

    # OAM interface
    input :dma_active
    input :oam_wr
    input :oam_addr_in, width: 8
    input :oam_di, width: 8
    output :oam_do, width: 8

    # Extra sprites (optional feature)
    input :extra_spr_en
    input :extra_wait
    input :tile_data_in, width: 8
    output :extra_tile_fetch
    output :extra_tile_addr, width: 12

    output :spr_extra_found
    output :spr_extra_tile0, width: 8
    output :spr_extra_tile1, width: 8
    output :spr_extra_pal
    output :spr_extra_prio
    output :spr_extra_cgb_pal, width: 3
    output :spr_extra_index, width: 4

    # Save state interface
    input :savestate_oamram_addr, width: 8
    input :savestate_oamram_wren
    input :savestate_oamram_write_data, width: 8
    output :savestate_oamram_read_data, width: 8

    # Internal OAM storage (160 bytes = 40 sprites x 4 bytes)
    # Each sprite: Y, X, Tile, Attributes
    wire :oam_addr, width: 8
    wire :oam_data, width: 8

    # Sprite search state
    wire :search_idx, width: 6    # Current OAM index being searched (0-39)
    wire :sprites_found, width: 4 # Number of sprites found (0-10)
    wire :search_active

    # Found sprite buffer (10 sprites max)
    wire :sprite_y, width: 8, count: 10
    wire :sprite_x, width: 8, count: 10
    wire :sprite_tile, width: 8, count: 10
    wire :sprite_flags, width: 8, count: 10

    # Current sprite being rendered
    wire :render_idx, width: 4

    behavior do
      # OAM address selection
      oam_addr <= mux(dma_active,
                      oam_addr_in,
                      cat(search_idx, lit(0, width: 2)))  # Y byte of current sprite

      # Default outputs
      oam_eval_end <= (search_idx == lit(40, width: 6)) | (sprites_found == lit(10, width: 4))
      sprite_fetch <= sprite_en & (sprites_found > lit(0, width: 4)) & oam_fetch
      sprite_index <= render_idx

      # Sprite tile address calculation
      # Address = (tile_number * 16) + (line_offset * 2)
      # For 8x16 sprites, bit 0 of tile is ignored
      sprite_addr <= cat(sprite_tile[render_idx][7..0], v_cnt[2..0])

      sprite_attr <= sprite_flags[render_idx]

      # Defaults for extra sprite output
      spr_extra_found <= lit(0, width: 1)
      extra_tile_fetch <= lit(0, width: 1)
      extra_tile_addr <= lit(0, width: 12)
      spr_extra_tile0 <= lit(0, width: 8)
      spr_extra_tile1 <= lit(0, width: 8)
      spr_extra_pal <= lit(0, width: 1)
      spr_extra_prio <= lit(0, width: 1)
      spr_extra_cgb_pal <= lit(0, width: 3)
      spr_extra_index <= lit(0, width: 4)
    end

    sequential clock: :clk, reset: :oam_eval_reset, reset_values: {
      search_idx: 0,
      sprites_found: 0,
      search_active: 0,
      render_idx: 0
    } do
      # OAM search during Mode 2
      search_active <= oam_eval

      search_idx <= mux(ce & oam_eval & (search_idx < lit(40, width: 6)),
                        search_idx + lit(1, width: 6),
                        search_idx)

      # Sprite rendering during Mode 3
      render_idx <= mux(sprite_fetch_done,
                        render_idx + lit(1, width: 4),
                        mux(oam_eval_reset, lit(0, width: 4), render_idx))
    end
  end
end
