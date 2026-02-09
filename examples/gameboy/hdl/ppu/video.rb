# Game Boy PPU (Pixel Processing Unit)
# Corresponds to: reference/rtl/video.v
#
# The PPU handles:
# - Background tile rendering
# - Window tile rendering
# - Sprite/OBJ rendering
# - LCD timing and mode control
# - VRAM and OAM access arbitration
#
# PPU Modes (from STAT register):
# - Mode 0 (H-Blank): CPU can access VRAM and OAM
# - Mode 1 (V-Blank): CPU can access VRAM and OAM
# - Mode 2 (OAM Search): CPU can access VRAM only
# - Mode 3 (Drawing): CPU cannot access VRAM or OAM

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'
require_relative '../../../../lib/rhdl/dsl/memory'

module RHDL
  module Examples
    module GameBoy
      class Video < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential
    include RHDL::DSL::Memory

    input :reset
    input :clk
    input :ce              # 4 MHz CPU clock enable
    input :ce_n            # 4 MHz inverted clock enable
    input :ce_cpu          # CPU clock enable (4 or 8 MHz)
    input :is_gbc           # Game Boy Color mode
    input :isGBC_mode      # GBC mode enabled
    input :megaduck        # Megaduck mode

    input :boot_rom_en     # Boot ROM enabled

    # CPU interface
    input :cpu_sel_oam     # OAM access
    input :cpu_sel_reg     # Register access
    input :cpu_addr, width: 8   # CPU address (low byte)
    input :cpu_wr          # CPU write
    input :cpu_di, width: 8     # CPU data in
    output :cpu_do, width: 8    # CPU data out

    # LCD interface
    output :lcd_on
    output :lcd_clkena
    output :lcd_data, width: 15    # RGB555 pixel data
    output :lcd_data_gb, width: 2  # 2-bit DMG pixel data
    output :lcd_vsync

    # Interrupt outputs
    output :irq            # STAT interrupt
    output :vblank_irq     # VBlank interrupt

    # VRAM interface
    output :mode, width: 2
    output :oam_cpu_allow
    output :vram_cpu_allow
    output :vram_rd
    output :vram_addr, width: 13
    input :vram_data, width: 8

    # VRAM bank 1 (GBC)
    input :vram1_data, width: 8

    # DMA interface
    output :dma_rd
    output :dma_addr, width: 16
    input :dma_data, width: 8

    # Extra sprite feature
    input :extra_spr_en
    input :extra_wait

    # Save state interface (simplified)
    input :savestate_oamram_addr, width: 8
    input :savestate_oamram_wren
    input :savestate_oamram_write_data, width: 8
    output :savestate_oamram_read_data, width: 8

    # Internal registers
    # FF40 - LCDC (LCD Control)
    wire :lcdc, width: 8
    wire :lcdc_on              # Bit 7: LCD enable
    wire :lcdc_win_tile_map    # Bit 6: Window tile map select
    wire :lcdc_win_ena         # Bit 5: Window enable
    wire :lcdc_tile_data_sel   # Bit 4: BG/Window tile data select
    wire :lcdc_bg_tile_map     # Bit 3: BG tile map select
    wire :lcdc_spr_siz         # Bit 2: Sprite size (0=8x8, 1=8x16)
    wire :lcdc_spr_ena         # Bit 1: Sprite enable
    wire :lcdc_bg_ena          # Bit 0: BG enable (DMG) / BG priority (CGB)

    # FF41 - STAT (LCD Status)
    wire :stat, width: 8

    # FF42-FF43 - SCY, SCX (Scroll)
    wire :scy, width: 8
    wire :scx, width: 8

    # FF44 - LY (Line counter, read-only)
    wire :h_cnt, width: 7      # Horizontal counter (0-113 at 1MHz)
    wire :h_div_cnt, width: 2  # Divide by 4
    wire :v_cnt, width: 8      # Vertical counter (0-153)

    # FF45 - LYC (LY Compare)
    wire :lyc, width: 8

    # FF46 - DMA
    wire :dma_reg, width: 8
    wire :dma_active
    wire :dma_cnt, width: 10

    # FF47-FF49 - Palettes (DMG)
    wire :bgp, width: 8
    wire :obp0, width: 8
    wire :obp1, width: 8

    # FF4A-FF4B - WY, WX (Window position)
    wire :wy, width: 8
    wire :wx, width: 8

    # FF68-FF6B - Color palettes (GBC)
    wire :bgpi, width: 6
    wire :bgpi_ai
    wire :obpi, width: 6
    wire :obpi_ai
    wire :ff6c_opri
    wire :obj_prio_dmg_mode

    # GBC palette RAM (FF69/FF6B data ports)
    wire :bgpd_wren
    wire :bgpd_q, width: 8
    wire :obpd_wren
    wire :obpd_q, width: 8
    wire :bgpd_pix_lo_addr, width: 6
    wire :bgpd_pix_hi_addr, width: 6
    wire :bgpd_pix_lo_q, width: 8
    wire :bgpd_pix_hi_q, width: 8
    wire :gbc_bg_rgb555, width: 15

    # Mode signals
    wire :mode_wire, width: 2
    wire :mode_prev, width: 2
    wire :dmg_mode_transition_glitch
    wire :vblank
    wire :oam_eval
    wire :mode3
    wire :mode3_target, width: 8
    wire :mode3_scx_penalty, width: 8
    wire :mode3_window_penalty, width: 8
    wire :mode3_sprite_penalty, width: 8
    wire :window_line_for_mode3
    wire :line_reset
    wire :lyc_match_prev
    wire :stat_irq_level
    wire :stat_irq_prev
    wire :bg_pause_for_sprite

    # Rendering state
    wire :pcnt, width: 8       # Pixel counter (0-159)
    wire :win_line, width: 8   # Window line counter
    wire :win_col, width: 5    # Window column counter

    # Tile fetcher state
    wire :fetch_phase, width: 3     # 0-7: fetch phase within 8-pixel tile
    wire :tile_num, width: 8        # Current tile number from tile map
    wire :tile_data_lo, width: 8    # Low byte of tile row data
    wire :tile_data_hi, width: 8    # High byte of tile row data
    wire :tile_shift_lo, width: 8   # Active low bitplane shift register
    wire :tile_shift_hi, width: 8   # Active high bitplane shift register
    wire :tile_fetch_x, width: 8    # Tile fetch X (advances every tile)
    wire :pixel_ready               # First tile row fetched on current line
    wire :sprite_fetch_cycle, width: 3
    wire :sprite_fetch_c1
    wire :sprite_fetch_done
    wire :spr_tile_data0, width: 8
    wire :spr_tile_shift_0, width: 8
    wire :spr_tile_shift_1, width: 8
    wire :spr_pal_shift, width: 8
    wire :spr_prio_shift, width: 8
    wire :bg_tile_attr, width: 8    # Active BG tile attributes (GBC)
    wire :bg_tile_attr_new, width: 8

    # Calculated addresses and pixel data
    wire :bg_x, width: 8            # BG X position (SCX + pcnt)
    wire :bg_y, width: 8            # BG Y position (SCY + v_cnt)
    wire :win_x, width: 8           # Window X position (pcnt - (WX-7))
    wire :win_y, width: 8           # Window Y position (LY - WY)
    wire :win_start_x, width: 8     # Saturating WX-7 start column
    wire :window_start
    wire :window_start_raw
    wire :window_reset
    wire :window_ena
    wire :window_match
    wire :window_ena_prev
    wire :wy_match
    wire :wxy_match
    wire :wxy_match_d
    wire :window_glitch_delay
    wire :window_active             # Window pixel select for current dot
    wire :fetch_x, width: 8         # Tile fetch X (window or BG)
    wire :fetch_y, width: 8         # Tile fetch Y (window or BG)
    wire :tile_map_sel              # Tile map select (window/bg)
    wire :tile_map_addr, width: 13  # Address in tile map
    wire :tile_data_addr, width: 13 # Address of tile data
    wire :tile_line, width: 3
    wire :tile_line_eff, width: 3
    wire :pixel_in_tile, width: 3   # Which pixel in tile (0-7)
    wire :pixel_color, width: 2     # Raw 2-bit color from tile
    wire :palette_color, width: 2   # Color after palette lookup
    wire :sprite_pixel_data, width: 2
    wire :sprite_pixel_visible
    wire :sprite_palette_color, width: 2
    wire :bg_vram_data, width: 8
    wire :bg_vram_data_rev, width: 8
    wire :bg_vram_data_in, width: 8
    wire :spr_vram_data, width: 8
    wire :spr_vram_data_rev, width: 8
    wire :spr_vram_data_in, width: 8

    # Sprite/OAM interface
    wire :sprites_oam_eval_end
    wire :sprite_found
    wire :sprite_addr, width: 11
    wire :sprite_attr, width: 8
    wire :sprite_index, width: 4
    wire :sprites_oam_do, width: 8
    wire :oam_wr
    wire :oam_addr, width: 8
    wire :oam_di_mux, width: 8

    # GBC palette memories (64 bytes each)
    memory :bgpd_mem, depth: 64, width: 8 do |m|
      m.write_port clock: :clk, enable: :bgpd_wren, addr: :bgpi, data: :cpu_di
      m.async_read_port addr: :bgpi, output: :bgpd_q
      m.async_read_port addr: :bgpd_pix_lo_addr, output: :bgpd_pix_lo_q
      m.async_read_port addr: :bgpd_pix_hi_addr, output: :bgpd_pix_hi_q
    end

    memory :obpd_mem, depth: 64, width: 8 do |m|
      m.write_port clock: :clk, enable: :obpd_wren, addr: :obpi, data: :cpu_di
      m.async_read_port addr: :obpi, output: :obpd_q
    end

    # Sprite instance
    instance :sprites_unit, Sprites

    # Sprite engine wiring
    port :clk => [:sprites_unit, :clk]
    port :ce => [:sprites_unit, :ce]
    port :ce_cpu => [:sprites_unit, :ce_cpu]
    port :lcdc_spr_siz => [:sprites_unit, :size16]
    port :is_gbc => [:sprites_unit, :is_gbc]
    port :lcdc_spr_ena => [:sprites_unit, :sprite_en]
    port :lcdc_on => [:sprites_unit, :lcd_on]
    port :v_cnt => [:sprites_unit, :v_cnt]
    port :pcnt => [:sprites_unit, :h_cnt]
    port :mode3 => [:sprites_unit, :oam_fetch]
    port :line_reset => [:sprites_unit, :oam_eval_reset]
    port :sprite_fetch_c1 => [:sprites_unit, :sprite_fetch_c1]
    port :sprite_fetch_done => [:sprites_unit, :sprite_fetch_done]
    port :dma_active => [:sprites_unit, :dma_active]
    port :oam_wr => [:sprites_unit, :oam_wr]
    port :oam_addr => [:sprites_unit, :oam_addr_in]
    port :oam_di_mux => [:sprites_unit, :oam_di]
    port :extra_spr_en => [:sprites_unit, :extra_spr_en]
    port :extra_wait => [:sprites_unit, :extra_wait]
    port :spr_vram_data_in => [:sprites_unit, :tile_data_in]
    port :savestate_oamram_addr => [:sprites_unit, :savestate_oamram_addr]
    port :savestate_oamram_wren => [:sprites_unit, :savestate_oamram_wren]
    port :savestate_oamram_write_data => [:sprites_unit, :savestate_oamram_write_data]

    port [:sprites_unit, :oam_eval_end] => :sprites_oam_eval_end
    port [:sprites_unit, :sprite_fetch] => :sprite_found
    port [:sprites_unit, :sprite_addr] => :sprite_addr
    port [:sprites_unit, :sprite_attr] => :sprite_attr
    port [:sprites_unit, :sprite_index] => :sprite_index
    port [:sprites_unit, :oam_do] => :sprites_oam_do
    port [:sprites_unit, :savestate_oamram_read_data] => :savestate_oamram_read_data

    # Combinational logic
    behavior do
      # LCDC bit extraction (with Megaduck differences)
      lcdc_on <= mux(megaduck, lcdc[7], lcdc[7])
      lcdc_win_tile_map <= mux(megaduck, lcdc[3], lcdc[6])
      lcdc_win_ena <= mux(megaduck, lcdc[5], lcdc[5])
      lcdc_tile_data_sel <= mux(megaduck, lcdc[4], lcdc[4])
      lcdc_bg_tile_map <= mux(megaduck, lcdc[2], lcdc[3])
      lcdc_spr_siz <= mux(megaduck, lcdc[1], lcdc[2])
      lcdc_spr_ena <= mux(megaduck, lcdc[0], lcdc[1])
      lcdc_bg_ena <= mux(megaduck, lcdc[6], lcdc[0]) | (is_gbc & isGBC_mode)

      # LCD on output
      lcd_on <= lcdc_on

      # VBlank detection
      vblank <= (v_cnt >= lit(144, width: 8))

      # Mode timing (at 1MHz h_cnt rate, 114 values per line)
      # Mode 2 (OAM Search): h_cnt 0-19 (80 dots)
      # Mode 3 (Drawing):    h_cnt 20-~63 (variable)
      # Mode 0 (HBlank):     h_cnt 63-113
      # OAM eval only active when LCD is on
      oam_eval <= lcdc_on & ~vblank & (h_cnt < lit(20, width: 7))
      line_reset <= ~lcdc_on | (ce & (h_div_cnt == lit(0, width: 2)) & (h_cnt == lit(0, width: 7)))

      # OAM bus arbitration (CPU/DMA -> sprite engine memory)
      oam_addr <= mux(dma_active, dma_addr[7..0], cpu_addr)
      oam_di_mux <= mux(dma_active, dma_data, cpu_di)
      oam_wr <= mux(dma_active,
                    dma_cnt[1..0] == lit(2, width: 2),
                    cpu_wr & cpu_sel_oam & oam_cpu_allow)

      # Mode3 duration tracks fine scroll and a first-window-fetch penalty.
      mode3_scx_penalty <= cat(lit(0, width: 5), scx[2..0])
      window_line_for_mode3 <= lcdc_win_ena & (v_cnt[7..0] >= wy[7..0]) & (wx[7..0] < lit(167, width: 8))
      mode3_window_penalty <= mux(window_line_for_mode3, lit(6, width: 8), lit(0, width: 8))
      # Sprite pressure stretches mode 3 further; extra sprite mode models
      # higher fetch demand as in reference timing behavior.
      mode3_sprite_penalty <= mux(lcdc_spr_ena & extra_spr_en, lit(8, width: 8),
                                  mux(lcdc_spr_ena, lit(4, width: 8), lit(0, width: 8)))
      mode3_target <= lit(160, width: 8) + mode3_scx_penalty + mode3_window_penalty + mode3_sprite_penalty
      # Mode3 only active when LCD is on (allowing VRAM access when LCD is disabled)
      mode3 <= lcdc_on & ~vblank & (h_cnt >= lit(20, width: 7)) & (pcnt < mode3_target)
      sprite_fetch_c1 <= sprite_fetch_cycle == lit(1, width: 3)
      sprite_fetch_done <= sprite_fetch_cycle == lit(5, width: 3)
      # Sprite fetch pauses BG shifter/counter progression.
      bg_pause_for_sprite <= mode3 & lcdc_spr_ena & (sprite_fetch_cycle != lit(0, width: 3))

      # LCD pixel output during mode 3.
      # Pixels are valid only after the first tile row has been fetched.
      lcd_clkena <= mode3 & lcdc_on & pixel_ready & (pcnt < lit(160, width: 8)) & ce

      # =======================================================================
      # Tile Fetcher - Calculate VRAM addresses for BG tiles
      # =======================================================================

      # Background/window position calculation.
      # The fetch side is tile-stepped (tile_fetch_x), while output uses shift
      # registers loaded once a full tile row fetch completes.
      bg_x <= (scx + pcnt)[7..0]
      bg_y <= (scy + v_cnt)[7..0]
      win_start_x <= mux(wx > lit(7, width: 8), wx - lit(7, width: 8), lit(0, width: 8))
      win_x <= (pcnt - win_start_x)[7..0]
      win_y <= (v_cnt - wy)[7..0]
      wxy_match <= wy_match & (pcnt == win_start_x)
      # DMG WX=0 + SCX=7 edge behavior: hold window start until a pixel is
      # already being output so first-fetch alignment matches reference timing.
      window_glitch_delay <= (wx == lit(0, width: 8)) & (scx[2..0] == lit(7, width: 3))
      window_start_raw <= ((~bg_pause_for_sprite) & wxy_match) | wxy_match_d
      window_start <= (~window_match) & lcdc_win_ena & window_start_raw &
                      ((~window_glitch_delay) | pixel_ready)
      window_reset <= (~mode3) | (~lcdc_win_ena)
      window_ena <= window_match & (~window_reset)
      window_active <= window_ena
      fetch_x <= mux(window_active, cat(win_col, lit(0, width: 3)), tile_fetch_x)
      fetch_y <= mux(window_active, win_line, bg_y)
      tile_map_sel <= mux(window_active, lcdc_win_tile_map, lcdc_bg_tile_map)
      pixel_in_tile <= lit(7, width: 3)

      # Tile map address calculation
      # Tile map is 32x32 tiles, each tile is 8x8 pixels
      # Tile map 0: 0x9800 = VRAM 0x1800
      # Tile map 1: 0x9C00 = VRAM 0x1C00
      # Address = base + (y_tile * 32) + x_tile
      # where y_tile = fetch_y[7:3], x_tile = fetch_x[7:3]
      tile_map_addr <= mux(tile_map_sel,
                           cat(lit(0b111, width: 3), fetch_y[7..3], fetch_x[7..3]),    # 0x1C00 + offset
                           cat(lit(0b110, width: 3), fetch_y[7..3], fetch_x[7..3]))    # 0x1800 + offset

      tile_line <= fetch_y[2..0]
      tile_line_eff <= mux(is_gbc & isGBC_mode & bg_tile_attr_new[6],
                           ~tile_line,
                           tile_line)

      # Tile data address calculation
      # Each tile is 16 bytes (2 bytes per row, 8 rows)
      # When LCDC bit 4 = 1: tiles 0-255 at 0x8000 (VRAM 0x0000)
      # When LCDC bit 4 = 0: tiles -128 to 127 at 0x8800 (VRAM 0x0800), tile 0 at 0x9000
      # Address = base + tile_num * 16 + (fetch_y % 8) * 2
      tile_data_addr <= mux(lcdc_tile_data_sel,
                            # Mode 1: unsigned, base 0x0000
                            cat(lit(0, width: 1), tile_num, tile_line_eff, lit(0, width: 1)),
                            # Mode 0: signed, base 0x0800 with XOR bias.
                            # This maps tile 0 -> 0x1000, -128 -> 0x0800, +127 -> 0x17F0.
                            cat(lit(0, width: 1), (tile_num ^ lit(0x80, width: 8)), tile_line_eff, lit(0, width: 1)) +
                            lit(0x0800, width: 13))

      # VRAM address mux based on fetch phase
      # Phase 0: Read tile map entry
      # Phase 2: Read tile data low byte
      # Phase 4: Read tile data high byte
      bg_vram_addr = mux(fetch_phase[2..1] == lit(0, width: 2), tile_map_addr,
                     mux(fetch_phase[2..1] == lit(1, width: 2), tile_data_addr,
                     mux(fetch_phase[2..1] == lit(2, width: 2), tile_data_addr + lit(1, width: 13),
                         tile_map_addr)))
      sprite_vram_addr = mux(sprite_fetch_cycle[2..1] == lit(1, width: 2),
                             cat(lit(0, width: 1), sprite_addr, lit(0, width: 1)),
                             cat(lit(0, width: 1), sprite_addr, lit(1, width: 1)))
      vram_addr <= mux(mode3 & (sprite_fetch_cycle != lit(0, width: 3)),
                       sprite_vram_addr,
                       bg_vram_addr)

      # GBC tile attribute handling:
      # - bit 3: tile data bank (VRAM0/VRAM1)
      # - bit 5: X flip (bit-reverse fetched tile row bytes)
      bg_vram_data <= mux(is_gbc & isGBC_mode & bg_tile_attr_new[3], vram1_data, vram_data)
      bg_vram_data_rev <= cat(bg_vram_data[0], bg_vram_data[1], bg_vram_data[2], bg_vram_data[3],
                              bg_vram_data[4], bg_vram_data[5], bg_vram_data[6], bg_vram_data[7])
      bg_vram_data_in <= mux(is_gbc & isGBC_mode & bg_tile_attr_new[5], bg_vram_data_rev, bg_vram_data)
      spr_vram_data <= mux(is_gbc & isGBC_mode & sprite_attr[3], vram1_data, vram_data)
      spr_vram_data_rev <= cat(spr_vram_data[0], spr_vram_data[1], spr_vram_data[2], spr_vram_data[3],
                               spr_vram_data[4], spr_vram_data[5], spr_vram_data[6], spr_vram_data[7])
      spr_vram_data_in <= mux(sprite_attr[5], spr_vram_data_rev, spr_vram_data)

      # Extract 2-bit pixel color from active shift registers.
      pixel_color <= mux(pixel_ready,
                         cat(tile_shift_hi[7], tile_shift_lo[7]),
                         lit(0, width: 2))

      # Apply BGP palette
      # BGP register: bits 7-6 = color 3, bits 5-4 = color 2, bits 3-2 = color 1, bits 1-0 = color 0
      palette_color <= mux(pixel_color == lit(0, width: 2), bgp[1..0],
                       mux(pixel_color == lit(1, width: 2), bgp[3..2],
                       mux(pixel_color == lit(2, width: 2), bgp[5..4],
                           bgp[7..6])))

      # GBC BG palette lookup (FF69): index = {attr[2:0], color[1:0], byte_sel}
      bgpd_pix_lo_addr <= cat(bg_tile_attr[2..0], pixel_color, lit(0, width: 1))
      bgpd_pix_hi_addr <= cat(bg_tile_attr[2..0], pixel_color, lit(1, width: 1))
      gbc_bg_rgb555 <= cat(bgpd_pix_hi_q[6..0], bgpd_pix_lo_q)

      # Sprite pixel pipeline (DMG priority model).
      sprite_pixel_data <= cat(spr_tile_shift_1[7], spr_tile_shift_0[7])
      sprite_pixel_visible <= lcdc_spr_ena & (sprite_pixel_data != lit(0, width: 2)) &
                              ((pixel_color == lit(0, width: 2)) | ~spr_prio_shift[7])
      sprite_obp = mux(spr_pal_shift[7], obp1, obp0)
      sprite_palette_color <= mux(sprite_pixel_data == lit(0, width: 2), sprite_obp[1..0],
                              mux(sprite_pixel_data == lit(1, width: 2), sprite_obp[3..2],
                              mux(sprite_pixel_data == lit(2, width: 2), sprite_obp[5..4],
                                  sprite_obp[7..6])))

      # Output pixel data
      # When BG is disabled, output color 0 (white on DMG)
      lcd_data_gb <= mux(lcd_clkena,
                        mux(sprite_pixel_visible,
                            sprite_palette_color,
                            mux(lcdc_bg_ena, palette_color, lit(0, width: 2))),
                        lit(0, width: 2))

      # RGB555 output (for GBC compatibility - just grayscale for now)
      sprite_rgb555 = mux(sprite_palette_color == lit(0, width: 2), lit(0x7FFF, width: 15),
                      mux(sprite_palette_color == lit(1, width: 2), lit(0x5294, width: 15),
                      mux(sprite_palette_color == lit(2, width: 2), lit(0x294A, width: 15),
                          lit(0x0000, width: 15))))
      lcd_data <= mux(lcd_clkena,
                     mux(is_gbc & isGBC_mode,
                         mux(sprite_pixel_visible, sprite_rgb555, gbc_bg_rgb555),
                         mux(sprite_pixel_visible,
                             sprite_rgb555,
                             mux(palette_color == lit(0, width: 2), lit(0x7FFF, width: 15),  # White
                             mux(palette_color == lit(1, width: 2), lit(0x5294, width: 15),  # Light gray
                             mux(palette_color == lit(2, width: 2), lit(0x294A, width: 15),  # Dark gray
                                 lit(0x0000, width: 15)))))),  # Black
                     lit(0, width: 15))

      # VSync signal - high during first line of VBlank
      lcd_vsync <= (v_cnt == lit(144, width: 8)) & (h_cnt < lit(20, width: 7))

      # Mode calculation
      mode_wire <= mux(vblank,
                       lit(1, width: 2),  # Mode 1: VBlank
                       mux(oam_eval,
                           lit(2, width: 2),  # Mode 2: OAM search
                           mux(mode3,
                               lit(3, width: 2),  # Mode 3: Drawing
                               lit(0, width: 2))))  # Mode 0: HBlank

      dmg_mode_transition_glitch <= ~is_gbc & ~isGBC_mode &
                                    (mode_prev == lit(1, width: 2)) &
                                    (mode_wire == lit(2, width: 2))
      mode <= mux(dmg_mode_transition_glitch, lit(0, width: 2), mode_wire)

      # CPU access control
      oam_cpu_allow <= ~(oam_eval | mode3 | dma_active)
      vram_cpu_allow <= ~mode3

      # VRAM read always active during mode 3
      vram_rd <= mode3

      # DMA address
      dma_addr <= cat(dma_reg, dma_cnt[9..2])
      dma_rd <= dma_active

      # GBC palette data ports
      bgpd_wren <= ce_cpu & cpu_sel_reg & cpu_wr & is_gbc & (cpu_addr == lit(0x69, width: 8)) & isGBC_mode & vram_cpu_allow
      obpd_wren <= ce_cpu & cpu_sel_reg & cpu_wr & is_gbc & (cpu_addr == lit(0x6B, width: 8)) & isGBC_mode & vram_cpu_allow

      # Interrupts
      # Reference contract: video exports level-style interrupt sources and the
      # top-level IF logic in gb.rb latches rising edges.
      lyc_match = lyc == v_cnt
      int_lyc = lcdc_on & stat[6] & lyc_match
      int_oam = lcdc_on & stat[5] & (mode_wire == lit(2, width: 2))
      int_vbl = lcdc_on & stat[4] & (mode_wire == lit(1, width: 2))
      int_hbl = lcdc_on & stat[3] & (mode_wire == lit(0, width: 2)) & ~vblank
      stat_irq_level <= int_lyc | int_oam | int_hbl | int_vbl
      irq <= stat_irq_level & ~stat_irq_prev

      # VBlank source for IF bit 0: active for mode 1.
      vblank_irq <= lcdc_on & (mode_wire == lit(1, width: 2))

      # CPU read data mux
      cpu_do_base = mux(cpu_sel_oam, sprites_oam_do,
                        case_select(cpu_addr, {
                          0x40 => lcdc,
                          0x41 => cat(lit(1, width: 1), stat[6..3], lyc == v_cnt, mode),
                          0x42 => scy,
                          0x43 => scx,
                          0x44 => v_cnt,
                          0x45 => lyc,
                          0x46 => dma_reg,
                          0x47 => bgp,
                          0x48 => obp0,
                          0x49 => obp1,
                          0x4A => wy,
                          0x4B => wx
                        }, default: lit(0xFF, width: 8)))
      cpu_do_gbc = cpu_do_base
      cpu_do_gbc = mux(cpu_addr == lit(0x68, width: 8), cat(bgpi_ai, lit(1, width: 1), bgpi), cpu_do_gbc)
      cpu_do_gbc = mux((cpu_addr == lit(0x69, width: 8)) & isGBC_mode & vram_cpu_allow, bgpd_q, cpu_do_gbc)
      cpu_do_gbc = mux(cpu_addr == lit(0x6A, width: 8), cat(obpi_ai, lit(1, width: 1), obpi), cpu_do_gbc)
      cpu_do_gbc = mux((cpu_addr == lit(0x6B, width: 8)) & isGBC_mode & vram_cpu_allow, obpd_q, cpu_do_gbc)
      cpu_do_gbc = mux(cpu_addr == lit(0x6C, width: 8), cat(lit(0x7F, width: 7), ff6c_opri), cpu_do_gbc)
      cpu_do <= mux(is_gbc, cpu_do_gbc, cpu_do_base)
    end

    # Sequential logic
    # Note: LCDC initialized to 0x91 (post-boot-ROM state: LCD on, BG enabled)
    # This allows simulation without running the boot ROM
    sequential clock: :clk, reset: :reset, reset_values: {
      lcdc: 0x91,
      stat: 0x00,
      scy: 0x00,
      scx: 0x00,
      lyc: 0x00,
      dma_reg: 0x00,
      bgp: 0xFC,
      obp0: 0xFF,
      obp1: 0xFF,
      wy: 0x00,
      wx: 0x00,
      h_cnt: 0,
      h_div_cnt: 0,
      v_cnt: 0,
      dma_active: 0,
      dma_cnt: 0,
      pcnt: 0,
      win_line: 0,
      win_col: 0,
      fetch_phase: 0,
      tile_num: 0,
      tile_data_lo: 0,
      tile_data_hi: 0,
      tile_shift_lo: 0,
      tile_shift_hi: 0,
      tile_fetch_x: 0,
      pixel_ready: 0,
      sprite_fetch_cycle: 0,
      spr_tile_data0: 0,
      spr_tile_shift_0: 0,
      spr_tile_shift_1: 0,
      spr_pal_shift: 0,
      spr_prio_shift: 0,
      bg_tile_attr: 0,
      bg_tile_attr_new: 0,
      bgpi: 0,
      bgpi_ai: 0,
      obpi: 0,
      obpi_ai: 0,
      ff6c_opri: 0,
      obj_prio_dmg_mode: 0,
      window_match: 0,
      window_ena_prev: 0,
      wy_match: 0,
      wxy_match_d: 0,
      mode_prev: 0,
      lyc_match_prev: 0,
      stat_irq_prev: 0
    } do
      # Horizontal/vertical timing counters.
      # Match DMG behavior more closely: when LCD is off, LY timing resets.
      h_div_cnt <= mux(~lcdc_on,
                       lit(0, width: 2),
                       mux(ce, h_div_cnt + lit(1, width: 2), h_div_cnt))

      # Reference timing:
      # - h_clk_en fires when h_div_cnt == 0
      # - h_clk_en_neg fires when h_div_cnt == 2
      h_cnt <= mux(~lcdc_on,
                   lit(0, width: 7),
                   mux(ce & (h_div_cnt == lit(0, width: 2)),
                       mux(h_cnt == lit(113, width: 7),
                           lit(0, width: 7),
                           h_cnt + lit(1, width: 7)),
                       h_cnt))

      # Vertical counter (0-153)
      v_cnt <= mux(~lcdc_on,
                   lit(0, width: 8),
                   mux(ce & (h_div_cnt == lit(2, width: 2)) & (h_cnt == lit(113, width: 7)),
                       mux(v_cnt == lit(153, width: 8),
                           lit(0, width: 8),
                           v_cnt + lit(1, width: 8)),
                       v_cnt))

      # Pixel counter for Mode 3 rendering.
      # Reset at start of mode 3 (h_cnt == 20, h_div_cnt == 0), then increment
      # each `ce` tick while in mode 3 until 160 visible pixels are produced.
      pcnt <= mux(~lcdc_on,
                  lit(0, width: 8),
                  mux(ce & (h_div_cnt == lit(0, width: 2)) & (h_cnt == lit(20, width: 7)),
                      lit(0, width: 8),  # Reset at start of mode 3
                      mux(ce & mode3 & pixel_ready & (pcnt < mode3_target) & ~bg_pause_for_sprite,
                          pcnt + lit(1, width: 8),  # Increment during mode 3
                          pcnt)))

      # Tile fetcher phase counter
      # Cycles through 0-7 for each 8-pixel tile
      # Phase 0-1: Fetch tile map entry
      # Phase 2-3: Fetch tile data low
      # Phase 4-5: Fetch tile data high
      # Phase 6-7: Output pixels (data already fetched)
      fetch_phase <= mux(~lcdc_on | ~mode3,
                         lit(0, width: 3),
                         mux(ce & window_start,
                             lit(0, width: 3),
                             mux(ce,
                             mux(fetch_phase == lit(7, width: 3),
                                 lit(0, width: 3),
                                 fetch_phase + lit(1, width: 3)),
                                 fetch_phase)))

      # Tile fetch X starts from SCX at mode 3 start and advances one tile
      # every fetch-phase wrap.
      tile_fetch_x <= mux(~lcdc_on,
                          lit(0, width: 8),
                          mux(ce & (h_div_cnt == lit(0, width: 2)) & (h_cnt == lit(20, width: 7)),
                              scx,
                              mux(ce & mode3 & (fetch_phase == lit(7, width: 3)),
                                  tile_fetch_x + lit(8, width: 8),
                                  tile_fetch_x)))

      # Sprite fetch pipeline (6 cycles per sprite tile row).
      sprite_fetch_cycle <= mux(~lcdc_on | ~mode3 | ~lcdc_spr_ena,
                                lit(0, width: 3),
                                mux(ce,
                                    mux(sprite_fetch_cycle != lit(0, width: 3),
                                        mux(sprite_fetch_cycle == lit(5, width: 3),
                                            lit(0, width: 3),
                                            sprite_fetch_cycle + lit(1, width: 3)),
                                        mux(sprite_found & pixel_ready,
                                            lit(1, width: 3),
                                            lit(0, width: 3))),
                                    sprite_fetch_cycle))

      # Window position tracking mirrors the reference model:
      # - line increments when window output turns off
      # - column increments per tile fetch while window is active
      wy_match <= mux(~lcdc_on | vblank,
                      lit(0, width: 1),
                      mux(ce & lcdc_win_ena & (v_cnt == wy),
                          lit(1, width: 1),
                          wy_match))
      wxy_match_d <= mux(~lcdc_on | ~mode3,
                         lit(0, width: 1),
                         mux(ce & ~bg_pause_for_sprite,
                             wxy_match,
                             wxy_match_d))
      window_match <= mux(~lcdc_on | window_reset,
                          lit(0, width: 1),
                          mux(ce & window_start,
                              lit(1, width: 1),
                              window_match))
      window_ena_prev <= mux(~lcdc_on,
                             lit(0, width: 1),
                             mux(ce,
                                 window_ena,
                                 window_ena_prev))
      win_line <= mux(~lcdc_on | vblank,
                      lit(0, width: 8),
                      mux(ce & window_ena_prev & ~window_ena,
                          win_line + lit(1, width: 8),
                          win_line))
      win_col <= mux(~lcdc_on | window_reset,
                     lit(0, width: 5),
                     mux(ce & window_ena & (fetch_phase == lit(7, width: 3)),
                         win_col + lit(1, width: 5),
                         win_col))

      # Capture tile number from VRAM read
      tile_num <= mux(ce & mode3 & (fetch_phase == lit(1, width: 3)),
                      vram_data,
                      tile_num)
      bg_tile_attr_new <= mux(ce & mode3 & (fetch_phase == lit(1, width: 3)) & is_gbc & isGBC_mode,
                              vram1_data,
                              bg_tile_attr_new)

      # Capture tile data low byte
      tile_data_lo <= mux(ce & mode3 & (fetch_phase == lit(3, width: 3)),
                          bg_vram_data_in,
                          tile_data_lo)

      # Capture tile data high byte
      tile_data_hi <= mux(ce & mode3 & (fetch_phase == lit(5, width: 3)),
                          bg_vram_data_in,
                          tile_data_hi)

      # Capture sprite data bytes while sprite fetch is active.
      sprite_obj0_rd = ce & mode3 & sprite_fetch_cycle[0] & (sprite_fetch_cycle[2..1] == lit(1, width: 2))
      sprite_obj1_rd = ce & mode3 & sprite_fetch_cycle[0] & (sprite_fetch_cycle[2..1] == lit(2, width: 2))
      spr_tile_data0 <= mux(sprite_obj0_rd, spr_vram_data_in, spr_tile_data0)

      # Pixel shift registers:
      # - load once high-byte fetch completes (phase 5)
      # - then shift one pixel each active output cycle
      load_tile = ce & mode3 & (fetch_phase == lit(5, width: 3))
      load_sprite = sprite_obj1_rd
      shift_pixel = ce & mode3 & pixel_ready & (pcnt < lit(160, width: 8)) & ~bg_pause_for_sprite

      tile_shift_lo <= mux(load_tile,
                           tile_data_lo,
                           mux(shift_pixel,
                               cat(tile_shift_lo[6..0], lit(0, width: 1)),
                               tile_shift_lo))
      tile_shift_hi <= mux(load_tile,
                           tile_data_hi,
                           mux(shift_pixel,
                               cat(tile_shift_hi[6..0], lit(0, width: 1)),
                               tile_shift_hi))
      spr_tile_shift_0 <= mux(load_sprite,
                              spr_tile_data0,
                              mux(shift_pixel,
                                  cat(spr_tile_shift_0[6..0], lit(0, width: 1)),
                                  spr_tile_shift_0))
      spr_tile_shift_1 <= mux(load_sprite,
                              spr_vram_data_in,
                              mux(shift_pixel,
                                  cat(spr_tile_shift_1[6..0], lit(0, width: 1)),
                                  spr_tile_shift_1))
      spr_pal_shift <= mux(load_sprite,
                           mux(sprite_attr[4], lit(0xFF, width: 8), lit(0, width: 8)),
                           mux(shift_pixel,
                               cat(spr_pal_shift[6..0], lit(0, width: 1)),
                               spr_pal_shift))
      spr_prio_shift <= mux(load_sprite,
                            mux(sprite_attr[7], lit(0xFF, width: 8), lit(0, width: 8)),
                            mux(shift_pixel,
                                cat(spr_prio_shift[6..0], lit(0, width: 1)),
                                spr_prio_shift))
      bg_tile_attr <= mux(load_tile, bg_tile_attr_new, bg_tile_attr)

      pixel_ready <= mux(~lcdc_on | ~mode3,
                         lit(0, width: 1),
                         mux(window_start,
                             lit(0, width: 1),
                             mux(load_tile,
                             lit(1, width: 1),
                             pixel_ready)))

      # DMA engine
      dma_active <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x46, width: 8)),
                        lit(1, width: 1),
                        mux(dma_cnt == lit(639, width: 10),  # 160*4-1
                            lit(0, width: 1),
                            dma_active))

      dma_cnt <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x46, width: 8)),
                     lit(0, width: 10),
                     mux(dma_active & ce_cpu,
                         dma_cnt + lit(1, width: 10),
                         dma_cnt))

      # Register writes
      lcdc <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x40, width: 8)),
                  cpu_di, lcdc)
      stat <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x41, width: 8)),
                  cpu_di, stat)
      scy <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x42, width: 8)),
                 cpu_di, scy)
      scx <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x43, width: 8)),
                 cpu_di, scx)
      lyc <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x45, width: 8)),
                 cpu_di, lyc)
      dma_reg <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x46, width: 8)),
                     cpu_di, dma_reg)
      bgp <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x47, width: 8)),
                 cpu_di, bgp)
      obp0 <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x48, width: 8)),
                  cpu_di, obp0)
      obp1 <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x49, width: 8)),
                  cpu_di, obp1)
      wy <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x4A, width: 8)),
                cpu_di, wy)
      wx <= mux(ce_cpu & cpu_sel_reg & cpu_wr & (cpu_addr == lit(0x4B, width: 8)),
                cpu_di, wx)

      # GBC palette registers (FF68-FF6C)
      gbc_reg_write = ce_cpu & cpu_sel_reg & cpu_wr & is_gbc
      write_bgpi = gbc_reg_write & (cpu_addr == lit(0x68, width: 8))
      write_bgpd = gbc_reg_write & (cpu_addr == lit(0x69, width: 8)) & isGBC_mode
      write_obpi = gbc_reg_write & (cpu_addr == lit(0x6A, width: 8))
      write_obpd = gbc_reg_write & (cpu_addr == lit(0x6B, width: 8)) & isGBC_mode
      write_opri = gbc_reg_write & (cpu_addr == lit(0x6C, width: 8))

      bgpi_next = bgpi
      bgpi_ai_next = bgpi_ai
      obpi_next = obpi
      obpi_ai_next = obpi_ai
      ff6c_opri_next = ff6c_opri
      obj_prio_dmg_mode_next = obj_prio_dmg_mode

      bgpi_next = mux(write_bgpi, cpu_di[5..0], bgpi_next)
      bgpi_ai_next = mux(write_bgpi, cpu_di[7], bgpi_ai_next)
      # Match reference: auto-increment applies even when VRAM write is blocked.
      bgpi_next = mux(write_bgpd & bgpi_ai, bgpi + lit(1, width: 6), bgpi_next)

      obpi_next = mux(write_obpi, cpu_di[5..0], obpi_next)
      obpi_ai_next = mux(write_obpi, cpu_di[7], obpi_ai_next)
      obpi_next = mux(write_obpd & obpi_ai, obpi + lit(1, width: 6), obpi_next)

      ff6c_opri_next = mux(write_opri & (boot_rom_en | isGBC_mode), cpu_di[0], ff6c_opri_next)
      obj_prio_dmg_mode_next = mux(write_opri & boot_rom_en, cpu_di[0], obj_prio_dmg_mode_next)

      bgpi <= bgpi_next
      bgpi_ai <= bgpi_ai_next
      obpi <= obpi_next
      obpi_ai <= obpi_ai_next
      ff6c_opri <= ff6c_opri_next
      obj_prio_dmg_mode <= obj_prio_dmg_mode_next

      # Latches for interrupt transition detection.
      mode_prev <= mux(~lcdc_on,
                       lit(0, width: 2),
                       mux(ce, mode_wire, mode_prev))
      lyc_match_prev <= mux(~lcdc_on,
                            lit(0, width: 1),
                            mux(ce, lyc == v_cnt, lyc_match_prev))
      stat_irq_prev <= mux(~lcdc_on,
                           lit(0, width: 1),
                           mux(ce, stat_irq_level, stat_irq_prev))
    end

    def initialize(name = nil, **kwargs)
      super(name, **kwargs)
      initialize_memories
    end
      end
    end
  end
end
