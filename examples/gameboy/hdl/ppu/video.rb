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

module GameBoy
  class Video < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

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

    # Mode signals
    wire :mode_wire, width: 2
    wire :vblank
    wire :oam_eval
    wire :mode3
    wire :hblank

    # Rendering state
    wire :pcnt, width: 8       # Pixel counter (0-159)
    wire :win_line, width: 8   # Window line counter
    wire :win_col, width: 5    # Window column counter

    # Tile fetcher state
    wire :fetch_phase, width: 3     # 0-7: fetch phase within 8-pixel tile
    wire :tile_num, width: 8        # Current tile number from tile map
    wire :tile_data_lo, width: 8    # Low byte of tile row data
    wire :tile_data_hi, width: 8    # High byte of tile row data

    # Calculated addresses and pixel data
    wire :bg_x, width: 8            # BG X position (SCX + pcnt)
    wire :bg_y, width: 8            # BG Y position (SCY + v_cnt)
    wire :tile_map_addr, width: 13  # Address in tile map
    wire :tile_data_addr, width: 13 # Address of tile data
    wire :pixel_in_tile, width: 3   # Which pixel in tile (0-7)
    wire :pixel_color, width: 2     # Raw 2-bit color from tile
    wire :palette_color, width: 2   # Color after palette lookup

    # Sprite instance
    instance :sprites_unit, Sprites

    # Clock to sprites
    port :clk => [:sprites_unit, :clk]
    port :ce => [:sprites_unit, :ce]

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
      # Mode 3 (Drawing):    h_cnt 20-62 (variable, ~172 dots)
      # Mode 0 (HBlank):     h_cnt 63-113
      oam_eval <= ~vblank & (h_cnt < lit(20, width: 7))
      mode3 <= ~vblank & (h_cnt >= lit(20, width: 7)) & (h_cnt < lit(63, width: 7))

      # LCD pixel output during mode 3
      # lcd_clkena pulses when we output a pixel (during visible drawing)
      lcd_clkena <= mode3 & lcdc_on & (pcnt < lit(160, width: 8)) & ce & (h_div_cnt == lit(0, width: 2))

      # =======================================================================
      # Tile Fetcher - Calculate VRAM addresses for BG tiles
      # =======================================================================

      # Background position calculation
      bg_x <= (scx + pcnt)[7..0]
      bg_y <= (scy + v_cnt)[7..0]

      # Pixel position within tile (0-7), from right to left for bit extraction
      pixel_in_tile <= lit(7, width: 3) - bg_x[2..0]

      # Tile map address calculation
      # Tile map is 32x32 tiles, each tile is 8x8 pixels
      # Tile map 0: 0x9800 = VRAM 0x1800
      # Tile map 1: 0x9C00 = VRAM 0x1C00
      # Address = base + (y_tile * 32) + x_tile
      # where y_tile = bg_y[7:3], x_tile = bg_x[7:3]
      tile_map_addr <= mux(lcdc_bg_tile_map,
                           cat(lit(0b111, width: 3), bg_y[7..3], bg_x[7..3]),    # 0x1C00 + offset
                           cat(lit(0b110, width: 3), bg_y[7..3], bg_x[7..3]))    # 0x1800 + offset

      # Tile data address calculation
      # Each tile is 16 bytes (2 bytes per row, 8 rows)
      # When LCDC bit 4 = 1: tiles 0-255 at 0x8000 (VRAM 0x0000)
      # When LCDC bit 4 = 0: tiles -128 to 127 at 0x8800 (VRAM 0x0800), tile 0 at 0x9000
      # Address = base + tile_num * 16 + (bg_y % 8) * 2
      tile_data_addr <= mux(lcdc_tile_data_sel,
                            # Mode 1: unsigned, base 0x0000
                            cat(lit(0, width: 1), tile_num, bg_y[2..0], lit(0, width: 1)),
                            # Mode 0: signed, base 0x1000 (tile 0 at 0x1000)
                            # For signed: tile_num is treated as signed, add 0x80 for unsigned offset
                            cat(lit(1, width: 1), (tile_num ^ lit(0x80, width: 8)), bg_y[2..0], lit(0, width: 1)))

      # VRAM address mux based on fetch phase
      # Phase 0: Read tile map entry
      # Phase 2: Read tile data low byte
      # Phase 4: Read tile data high byte
      vram_addr <= mux(fetch_phase[2..1] == lit(0, width: 2), tile_map_addr,
                   mux(fetch_phase[2..1] == lit(1, width: 2), tile_data_addr,
                   mux(fetch_phase[2..1] == lit(2, width: 2), tile_data_addr + lit(1, width: 13),
                       tile_map_addr)))

      # Extract 2-bit pixel color from tile data
      # Low bit from tile_data_lo, high bit from tile_data_hi
      pixel_color <= cat(tile_data_hi[pixel_in_tile], tile_data_lo[pixel_in_tile])

      # Apply BGP palette
      # BGP register: bits 7-6 = color 3, bits 5-4 = color 2, bits 3-2 = color 1, bits 1-0 = color 0
      palette_color <= mux(pixel_color == lit(0, width: 2), bgp[1..0],
                       mux(pixel_color == lit(1, width: 2), bgp[3..2],
                       mux(pixel_color == lit(2, width: 2), bgp[5..4],
                           bgp[7..6])))

      # Output pixel data
      # When BG is disabled, output color 0 (white on DMG)
      lcd_data_gb <= mux(lcd_clkena,
                        mux(lcdc_bg_ena, palette_color, lit(0, width: 2)),
                        lit(0, width: 2))

      # RGB555 output (for GBC compatibility - just grayscale for now)
      lcd_data <= mux(lcd_clkena,
                     mux(palette_color == lit(0, width: 2), lit(0x7FFF, width: 15),  # White
                     mux(palette_color == lit(1, width: 2), lit(0x5294, width: 15),  # Light gray
                     mux(palette_color == lit(2, width: 2), lit(0x294A, width: 15),  # Dark gray
                         lit(0x0000, width: 15)))),  # Black
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

      mode <= mode_wire

      # CPU access control
      oam_cpu_allow <= ~(oam_eval | mode3 | dma_active)
      vram_cpu_allow <= ~mode3

      # VRAM read always active during mode 3
      vram_rd <= mode3

      # DMA address
      dma_addr <= cat(dma_reg, dma_cnt[9..2])
      dma_rd <= dma_active

      # Interrupts
      vblank_irq <= (v_cnt == lit(144, width: 8)) & (h_cnt == lit(0, width: 7)) & (h_div_cnt == lit(0, width: 2))
      irq <= vblank_irq  # Simplified - real GB has more STAT interrupt sources

      # CPU read data mux
      cpu_do <= mux(cpu_sel_oam, lit(0xFF, width: 8),  # OAM read handled by sprites
                case_select(cpu_addr, {
                  0x40 => lcdc,
                  0x41 => cat(lit(1, width: 1), stat[6..3], lyc == v_cnt, mode_wire),
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
      tile_data_hi: 0
    } do
      # Horizontal counter (0-113 at 1MHz, so 0-454 at 4MHz with h_div_cnt)
      h_div_cnt <= mux(ce & lcdc_on, h_div_cnt + lit(1, width: 2), h_div_cnt)

      h_cnt <= mux(ce & lcdc_on & (h_div_cnt == lit(3, width: 2)),
                   mux(h_cnt == lit(113, width: 7),
                       lit(0, width: 7),
                       h_cnt + lit(1, width: 7)),
                   h_cnt)

      # Vertical counter (0-153)
      v_cnt <= mux(ce & lcdc_on & (h_div_cnt == lit(3, width: 2)) & (h_cnt == lit(113, width: 7)),
                   mux(v_cnt == lit(153, width: 8),
                       lit(0, width: 8),
                       v_cnt + lit(1, width: 8)),
                   v_cnt)

      # Pixel counter for Mode 3 rendering
      # Reset at start of mode 3 (h_cnt == 20), increment when outputting pixels
      pcnt <= mux(~lcdc_on,
                  lit(0, width: 8),
                  mux(ce & (h_div_cnt == lit(0, width: 2)) & (h_cnt == lit(20, width: 7)),
                      lit(0, width: 8),  # Reset at start of mode 3
                      mux(ce & (h_div_cnt == lit(0, width: 2)) &
                          (h_cnt >= lit(20, width: 7)) & (h_cnt < lit(63, width: 7)) &
                          (pcnt < lit(160, width: 8)) & ~vblank,
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
                         mux(ce,
                             mux(fetch_phase == lit(7, width: 3),
                                 lit(0, width: 3),
                                 fetch_phase + lit(1, width: 3)),
                             fetch_phase))

      # Capture tile number from VRAM read
      tile_num <= mux(ce & mode3 & (fetch_phase == lit(1, width: 3)),
                      vram_data,
                      tile_num)

      # Capture tile data low byte
      tile_data_lo <= mux(ce & mode3 & (fetch_phase == lit(3, width: 3)),
                          vram_data,
                          tile_data_lo)

      # Capture tile data high byte
      tile_data_hi <= mux(ce & mode3 & (fetch_phase == lit(5, width: 3)),
                          vram_data,
                          tile_data_hi)

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
    end
  end
end
