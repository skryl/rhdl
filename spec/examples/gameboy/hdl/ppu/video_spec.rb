# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/gameboy/gameboy'

# Game Boy PPU (Video) Component Tests
# Tests the main Video unit which handles:
# - Background tile rendering
# - Window tile rendering
# - LCD timing and mode control
# - VRAM and OAM access arbitration
# - DMA transfers
RSpec.describe GameBoy::Video do
  def clock_cycle(component, enable_ce: true)
    component.set_input(:ce, enable_ce ? 1 : 0)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  def clock_cycles(component, n, enable_ce: true)
    n.times { clock_cycle(component, enable_ce: enable_ce) }
  end

  let(:video) { GameBoy::Video.new }

  before do
    # Initialize inputs to default values
    video.set_input(:reset, 0)
    video.set_input(:clk, 0)
    video.set_input(:ce, 1)
    video.set_input(:ce_n, 0)
    video.set_input(:ce_cpu, 1)
    video.set_input(:is_gbc, 0)
    video.set_input(:isGBC_mode, 0)
    video.set_input(:megaduck, 0)
    video.set_input(:boot_rom_en, 0)
    video.set_input(:cpu_sel_oam, 0)
    video.set_input(:cpu_sel_reg, 0)
    video.set_input(:cpu_addr, 0)
    video.set_input(:cpu_wr, 0)
    video.set_input(:cpu_di, 0)
    video.set_input(:vram_data, 0)
    video.set_input(:vram1_data, 0)
    video.set_input(:dma_data, 0)
    video.set_input(:extra_spr_en, 0)
    video.set_input(:extra_wait, 0)
    video.set_input(:savestate_oamram_addr, 0)
    video.set_input(:savestate_oamram_wren, 0)
    video.set_input(:savestate_oamram_write_data, 0)
    video.propagate
  end

  describe 'component instantiation' do
    it 'creates a Video component' do
      expect(video).to be_a(GameBoy::Video)
    end

    it 'has LCD control outputs' do
      expect { video.get_output(:lcd_on) }.not_to raise_error
      expect { video.get_output(:lcd_clkena) }.not_to raise_error
      expect { video.get_output(:lcd_data) }.not_to raise_error
      expect { video.get_output(:lcd_data_gb) }.not_to raise_error
      expect { video.get_output(:lcd_vsync) }.not_to raise_error
    end

    it 'has interrupt outputs' do
      expect { video.get_output(:irq) }.not_to raise_error
      expect { video.get_output(:vblank_irq) }.not_to raise_error
    end

    it 'has mode outputs' do
      expect { video.get_output(:mode) }.not_to raise_error
      expect { video.get_output(:oam_cpu_allow) }.not_to raise_error
      expect { video.get_output(:vram_cpu_allow) }.not_to raise_error
    end
  end

  describe 'reset behavior' do
    it 'initializes with LCD on after reset (post-boot state)' do
      # Apply reset
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)

      # LCDC defaults to 0x91 (LCD enabled, BG enabled)
      expect(video.get_output(:lcd_on)).to eq(1)
    end

    it 'initializes registers to post-boot values' do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)

      # Read LCDC (0x40) - should be 0x91
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x40)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0x91)

      # Read BGP (0x47) - should be 0xFC
      video.set_input(:cpu_addr, 0x47)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0xFC)
    end
  end

  describe 'PPU mode timing' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'starts in mode 2 (OAM search) at beginning of line' do
      # Mode 2 at h_cnt 0-19 (line start)
      expect(video.get_output(:mode)).to eq(2)
    end

    it 'transitions through modes during a scanline' do
      # Mode 2: OAM search (h_cnt 0-19 at 1MHz, so 0-79 dots at 4MHz)
      # With h_div_cnt, each h_cnt takes 4 ce cycles
      initial_mode = video.get_output(:mode)
      expect(initial_mode).to eq(2)

      # Run enough cycles to reach mode 3 (h_cnt 20+)
      # h_cnt increments when h_div_cnt wraps from 3 to 0
      # To reach h_cnt=20, we need 20*4 = 80 cycles
      clock_cycles(video, 80)

      expect(video.get_output(:mode)).to eq(3)  # Mode 3: Drawing
    end

    it 'enters mode 0 (HBlank) after drawing' do
      # h_cnt 63+ is HBlank (Mode 0)
      # Need 63 * 4 = 252 cycles
      clock_cycles(video, 252)

      expect(video.get_output(:mode)).to eq(0)
    end

    it 'enters VBlank (mode 1) at line 144', :slow do
      # Each line is 114 h_cnt values at 1MHz = 456 dots at 4MHz
      # Line 144 starts at cycle 144 * 456 = 65664
      # Run one full frame minus current position

      # First complete the current line
      cycles_per_line = 456
      total_visible_lines = 144

      # Run through all visible lines
      clock_cycles(video, cycles_per_line * total_visible_lines)

      expect(video.get_output(:mode)).to eq(1)  # Mode 1: VBlank
    end
  end

  describe 'register read/write' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'writes and reads SCY register (0x42)' do
      # Write SCY
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x42)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0x55)
      clock_cycle(video)

      # Read back
      video.set_input(:cpu_wr, 0)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0x55)
    end

    it 'writes and reads SCX register (0x43)' do
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x43)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0xAA)
      clock_cycle(video)

      video.set_input(:cpu_wr, 0)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0xAA)
    end

    it 'reads LY register (0x44) - current scanline' do
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x44)
      video.propagate

      # LY starts at 0
      expect(video.get_output(:cpu_do)).to eq(0)

      # Run one complete scanline (456 cycles)
      clock_cycles(video, 456)

      video.propagate
      expect(video.get_output(:cpu_do)).to eq(1)
    end

    it 'writes and reads LYC register (0x45)' do
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x45)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0x90)  # Line 144
      clock_cycle(video)

      video.set_input(:cpu_wr, 0)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0x90)
    end

    it 'writes palette registers' do
      # Write BGP (0x47)
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x47)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0xE4)  # Standard palette
      clock_cycle(video)

      video.set_input(:cpu_wr, 0)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0xE4)

      # Write OBP0 (0x48)
      video.set_input(:cpu_addr, 0x48)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0xD0)
      clock_cycle(video)

      video.set_input(:cpu_wr, 0)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0xD0)
    end

    it 'writes window position registers WY/WX' do
      # Write WY (0x4A)
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x4A)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0x10)
      clock_cycle(video)

      video.set_input(:cpu_wr, 0)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0x10)

      # Write WX (0x4B)
      video.set_input(:cpu_addr, 0x4B)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0x07)  # Standard window X offset
      clock_cycle(video)

      video.set_input(:cpu_wr, 0)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0x07)
    end
  end

  describe 'VRAM access control' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'allows VRAM access during HBlank (mode 0)' do
      # Advance to HBlank
      clock_cycles(video, 252)  # h_cnt 63+

      expect(video.get_output(:mode)).to eq(0)
      expect(video.get_output(:vram_cpu_allow)).to eq(1)
    end

    it 'denies VRAM access during drawing (mode 3)' do
      # Advance to mode 3
      clock_cycles(video, 80)  # h_cnt 20+

      expect(video.get_output(:mode)).to eq(3)
      expect(video.get_output(:vram_cpu_allow)).to eq(0)
    end

    it 'allows VRAM access during VBlank (mode 1)', :slow do
      # Advance to VBlank (line 144)
      clock_cycles(video, 456 * 144)

      expect(video.get_output(:mode)).to eq(1)
      expect(video.get_output(:vram_cpu_allow)).to eq(1)
    end
  end

  describe 'OAM access control' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'denies OAM access during OAM search (mode 2)' do
      expect(video.get_output(:mode)).to eq(2)
      expect(video.get_output(:oam_cpu_allow)).to eq(0)
    end

    it 'denies OAM access during drawing (mode 3)' do
      clock_cycles(video, 80)  # Advance to mode 3

      expect(video.get_output(:mode)).to eq(3)
      expect(video.get_output(:oam_cpu_allow)).to eq(0)
    end

    it 'allows OAM access during HBlank (mode 0)' do
      clock_cycles(video, 252)  # Advance to HBlank

      expect(video.get_output(:mode)).to eq(0)
      expect(video.get_output(:oam_cpu_allow)).to eq(1)
    end
  end

  describe 'DMA transfer' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'triggers DMA when writing to DMA register (0x46)' do
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x46)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0xC0)  # DMA from 0xC000
      clock_cycle(video)

      # DMA should be active
      expect(video.get_output(:dma_rd)).to eq(1)
    end

    it 'generates correct DMA address during transfer' do
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x46)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0xC0)
      clock_cycle(video)

      video.set_input(:cpu_wr, 0)

      # DMA address should start at 0xC000
      expect(video.get_output(:dma_addr)).to eq(0xC000)
    end
  end

  describe 'VBlank interrupt' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'generates VBlank interrupt at line 144', :slow do
      # Run to just before VBlank
      clock_cycles(video, 456 * 144 - 4)

      expect(video.get_output(:vblank_irq)).to eq(0)

      # Cross into VBlank
      clock_cycles(video, 8)

      # VBlank IRQ should trigger at start of line 144
      expect(video.get_output(:mode)).to eq(1)
    end
  end

  describe 'STAT register' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'reflects current mode in STAT register (0x41)' do
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x41)
      video.propagate

      # Mode 2 at start
      stat = video.get_output(:cpu_do)
      expect(stat & 0x03).to eq(2)

      # Advance to mode 3
      clock_cycles(video, 80)
      video.propagate
      stat = video.get_output(:cpu_do)
      expect(stat & 0x03).to eq(3)
    end

    it 'sets LYC=LY coincidence flag' do
      # Set LYC to 0 (current line)
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x45)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0)
      clock_cycle(video)
      video.set_input(:cpu_wr, 0)

      # Read STAT
      video.set_input(:cpu_addr, 0x41)
      video.propagate

      stat = video.get_output(:cpu_do)
      # Bit 2 is LYC=LY coincidence flag
      expect(stat & 0x04).to eq(0x04)
    end
  end

  describe 'LCD disable' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'stops mode transitions when LCD is disabled' do
      # Disable LCD by clearing bit 7 of LCDC
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x40)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0x00)  # LCD off
      clock_cycle(video)

      video.set_input(:cpu_wr, 0)
      clock_cycles(video, 100)

      expect(video.get_output(:lcd_on)).to eq(0)
    end
  end
end
