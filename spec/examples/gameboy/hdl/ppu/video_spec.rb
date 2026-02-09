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
RSpec.describe RHDL::Examples::GameBoy::Video do
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

  def sample_mode3(component, cycles:, vram_data:, vram1_data:)
    while component.get_output(:mode) != 3
      clock_cycle(component)
    end

    samples = []
    cycles.times do
      component.set_input(:vram_data, vram_data)
      component.set_input(:vram1_data, vram1_data)
      component.propagate
      samples << {
        vram_addr: component.get_output(:vram_addr),
        lcd: component.get_output(:lcd_data_gb),
        rgb: component.get_output(:lcd_data),
        clkena: component.get_output(:lcd_clkena)
      }
      clock_cycle(component)
    end
    samples
  end

  def first_visible_nonzero_pixel(samples)
    samples.find_index { |s| s[:clkena] == 1 && s[:lcd] != 0 }
  end

  def first_visible_rgb(samples)
    s = samples.find { |sample| sample[:clkena] == 1 }
    s && s[:rgb]
  end

  def first_visible_nonzero_rgb(samples)
    s = samples.find { |sample| sample[:clkena] == 1 && sample[:rgb] != 0 }
    s && s[:rgb]
  end

  def write_bgpd_entry(component, index, value)
    component.set_input(:cpu_sel_reg, 1)
    component.set_input(:cpu_addr, 0x68)
    component.set_input(:cpu_wr, 1)
    component.set_input(:cpu_di, index & 0x3F)
    clock_cycle(component)

    component.set_input(:cpu_addr, 0x69)
    component.set_input(:cpu_di, value & 0xFF)
    clock_cycle(component)
  end

  def seed_cgb_bg_palettes(component)
    # Palette 0, color 3 -> RGB555 0x001F
    write_bgpd_entry(component, 0x06, 0x1F)
    write_bgpd_entry(component, 0x07, 0x00)
    # Palette 3, color 3 -> RGB555 0x0180
    write_bgpd_entry(component, 0x1E, 0x80)
    write_bgpd_entry(component, 0x1F, 0x01)
    component.set_input(:cpu_wr, 0)
    component.set_input(:cpu_sel_reg, 0)
  end

  def reset_video(component)
    component.set_input(:reset, 1)
    clock_cycle(component)
    component.set_input(:reset, 0)
    clock_cycle(component)
  end

  def write_video_reg(component, addr, value)
    component.set_input(:cpu_sel_reg, 1)
    component.set_input(:cpu_addr, addr)
    component.set_input(:cpu_wr, 1)
    component.set_input(:cpu_di, value)
    clock_cycle(component)
    component.set_input(:cpu_wr, 0)
    component.set_input(:cpu_sel_reg, 0)
  end

  def write_oam_byte(component, addr, value)
    component.set_input(:savestate_oamram_addr, addr & 0xFF)
    component.set_input(:savestate_oamram_write_data, value & 0xFF)
    component.set_input(:savestate_oamram_wren, 1)
    clock_cycle(component)
    component.set_input(:savestate_oamram_wren, 0)
    clock_cycle(component)
  end

  def seed_oam_sprite(component, index:, y:, x:, tile:, attr:)
    base = index * 4
    write_oam_byte(component, base, y)
    write_oam_byte(component, base + 1, x)
    write_oam_byte(component, base + 2, tile)
    write_oam_byte(component, base + 3, attr)
  end

  def advance_to_next_line_start(component, max_cycles: 8_000)
    seen_nonzero = false
    max_cycles.times do
      component.propagate
      h_cnt = component.signal_val(:h_cnt)
      h_div = component.signal_val(:h_div_cnt)
      if h_cnt != 0 || h_div != 0
        seen_nonzero = true
      elsif seen_nonzero
        return
      end
      clock_cycle(component)
    end
    raise 'line start was not reached'
  end

  def wait_for_mode(component, target_mode, max_wait: 8_000)
    waited = 0
    while component.get_output(:mode) != target_mode && waited < max_wait
      clock_cycle(component)
      waited += 1
    end
    raise "mode #{target_mode} was not reached" if component.get_output(:mode) != target_mode
  end

  def sample_mode3_dynamic(component, cycles:, max_wait: 8_000)
    wait_for_mode(component, 3, max_wait: max_wait)
    samples = []
    cycles.times do
      component.propagate
      addr = component.get_output(:vram_addr)
      vram_data, vram1_data = block_given? ? yield(addr) : [0, 0]
      component.set_input(:vram_data, vram_data)
      component.set_input(:vram1_data, vram1_data)
      component.propagate
      samples << {
        vram_addr: component.get_output(:vram_addr),
        lcd: component.get_output(:lcd_data_gb),
        rgb: component.get_output(:lcd_data),
        clkena: component.get_output(:lcd_clkena),
        pcnt: component.signal_val(:pcnt)
      }
      clock_cycle(component)
    end
    samples
  end

  def measure_mode3_length(component, max_cycles: 800)
    wait_cycles = 0
    while component.get_output(:mode) != 3 && wait_cycles < max_cycles
      clock_cycle(component)
      wait_cycles += 1
    end
    raise 'mode 3 was not reached' if component.get_output(:mode) != 3

    mode3_cycles = 0
    while component.get_output(:mode) == 3 && mode3_cycles < max_cycles
      mode3_cycles += 1
      clock_cycle(component)
    end
    mode3_cycles
  end

  def capture_mode3_vram_addrs(component, cycles:, vram_data: 0x80, vram1_data: 0x00, max_wait: 8_000)
    waited = 0
    while component.get_output(:mode) != 3 && waited < max_wait
      clock_cycle(component)
      waited += 1
    end
    raise 'mode 3 was not reached' if component.get_output(:mode) != 3

    addrs = []
    cycles.times do
      component.set_input(:vram_data, vram_data)
      component.set_input(:vram1_data, vram1_data)
      component.propagate
      addrs << component.get_output(:vram_addr)
      clock_cycle(component)
    end
    addrs
  end

  def first_window_map_fetch(addrs)
    addrs.find_index { |addr| addr >= 0x1C00 && addr < 0x2000 }
  end

  def first_tile_data_fetch(addrs)
    addrs.find { |addr| addr < 0x1800 }
  end

  def sample_one_mode3_line(component, cycles: 32, vram_data: 0x80, vram1_data: 0x00)
    addrs = capture_mode3_vram_addrs(component, cycles: cycles, vram_data: vram_data, vram1_data: vram1_data)
    drain = 0
    while component.get_output(:mode) == 3 && drain < 4_000
      clock_cycle(component)
      drain += 1
    end
    addrs
  end

  let(:video) { RHDL::Examples::GameBoy::Video.new }

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
      expect(video).to be_a(RHDL::Examples::GameBoy::Video)
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

  # ============================================================================
  # Missing functionality tests (from reference comparison)
  # These tests verify features that should be implemented to match the
  # MiSTer reference implementation (reference/rtl/video.v)
  # ============================================================================

  describe 'Pixel FIFO' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'uses shift registers for background pixel serialization' do
      reset_video(video)
      samples = sample_mode3(video, cycles: 24, vram_data: 0x80, vram1_data: 0x00)
      nonzero_idx = samples.each_index.select { |i| samples[i][:clkena] == 1 && samples[i][:lcd] != 0 }

      expect(nonzero_idx.length).to be >= 3
      spacing = nonzero_idx.each_cons(2).map { |a, b| b - a }
      expect(spacing.uniq).to eq([8])
    end

    it 'uses shift registers for sprite pixel serialization' do
      reset_video(video)
      write_video_reg(video, 0x40, 0x93) # Enable sprites
      write_video_reg(video, 0x48, 0x00) # OBP0 maps sprite colors to color 0
      seed_oam_sprite(video, index: 0, y: 16, x: 8, tile: 1, attr: 0x00)
      advance_to_next_line_start(video)

      samples = sample_mode3_dynamic(video, cycles: 80) do |addr|
        # Keep BG as color 3 and provide sprite tile bits only on OBJ fetches.
        addr < 0x0200 ? [0xF0, 0x00] : [0xFF, 0x00]
      end

      sprite_pixels = samples.each_index.select { |i| samples[i][:clkena] == 1 && samples[i][:lcd] == 0 }
      longest_run = 0
      run = 0
      prev = nil
      sprite_pixels.each do |idx|
        run = (prev && idx == prev + 1) ? run + 1 : 1
        longest_run = [longest_run, run].max
        prev = idx
      end

      expect(longest_run).to be >= 4
    end

    it 'pauses background rendering during sprite fetch' do
      reset_video(video)
      write_video_reg(video, 0x40, 0x93) # Sprites enabled
      baseline = sample_mode3(video, cycles: 40, vram_data: 0x80, vram1_data: 0x00)
      baseline_idx = baseline.each_index.select { |i| baseline[i][:clkena] == 1 && baseline[i][:lcd] != 0 }

      reset_video(video)
      write_video_reg(video, 0x40, 0x93)
      seed_oam_sprite(video, index: 0, y: 16, x: 8, tile: 1, attr: 0x00)
      # Let the current line finish so OAM evaluation sees the seeded sprite.
      advance_to_next_line_start(video)
      paused = sample_mode3(video, cycles: 80, vram_data: 0x80, vram1_data: 0x00)
      paused_idx = paused.each_index.select { |i| paused[i][:clkena] == 1 && paused[i][:lcd] != 0 }

      baseline_spacing = baseline_idx.each_cons(2).map { |a, b| b - a }
      paused_spacing = paused_idx.each_cons(2).map { |a, b| b - a }

      expect(baseline_spacing.uniq).to eq([8])
      expect(paused_spacing.uniq).not_to eq([8])
      expect(paused_spacing.min).to be < 8
    end
  end

  describe 'Sprite X/Y Flip' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'supports horizontal flip via sprite attribute bit 5' do
      capture = lambda do |attr|
        reset_video(video)
        write_video_reg(video, 0x40, 0x93)
        write_video_reg(video, 0x48, 0x00)
        seed_oam_sprite(video, index: 0, y: 16, x: 8, tile: 1, attr: attr)
        advance_to_next_line_start(video)
        sample_mode3_dynamic(video, cycles: 80) do |addr|
          addr < 0x0200 ? [0x80, 0x00] : [0xFF, 0x00]
        end
      end

      normal = capture.call(0x00)
      xflip = capture.call(0x20)
      normal_hits = normal.each_index.select { |i| normal[i][:clkena] == 1 && normal[i][:lcd] == 0 }
      xflip_hits = xflip.each_index.select { |i| xflip[i][:clkena] == 1 && xflip[i][:lcd] == 0 }
      normal_first = normal_hits.find { |i| i > 14 }
      xflip_first = xflip_hits.find { |i| i > 14 }

      expect(normal_first).not_to be_nil
      expect(xflip_first).not_to be_nil
      expect(xflip_first).to be > normal_first
    end

    it 'supports vertical flip via sprite attribute bit 6' do
      capture_addrs = lambda do |attr|
        reset_video(video)
        write_video_reg(video, 0x40, 0x93)
        seed_oam_sprite(video, index: 0, y: 16, x: 8, tile: 1, attr: attr)
        advance_to_next_line_start(video)
        sample_mode3_dynamic(video, cycles: 60) { |_addr| [0xFF, 0x00] }
      end

      normal = capture_addrs.call(0x00).map { |s| s[:vram_addr] }.select { |a| a < 0x0200 }.uniq
      yflip = capture_addrs.call(0x40).map { |s| s[:vram_addr] }.select { |a| a < 0x0200 }.uniq

      expect(normal).to include(0x0010, 0x0011)
      expect(yflip).to include(0x001E, 0x001F)
    end
  end

  describe 'GBC Background Attributes' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)
    end

    it 'reads tile attributes from VRAM bank 1' do
      reset_video(video)
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)
      normal = sample_mode3(video, cycles: 6, vram_data: 0x01, vram1_data: 0x00)

      reset_video(video)
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)
      attr_from_vram1 = sample_mode3(video, cycles: 6, vram_data: 0x01, vram1_data: 0x40)

      # With vram1_data bit 6 set, Y-flip should alter the fetched tile-row address.
      expect(normal[2][:vram_addr]).to eq(0x0010)
      expect(attr_from_vram1[2][:vram_addr]).to eq(0x001E)
    end

    it 'supports background X-flip via attribute bit 5' do
      reset_video(video)
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)
      normal = sample_mode3(video, cycles: 16, vram_data: 0x01, vram1_data: 0x00)

      reset_video(video)
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)
      xflip = sample_mode3(video, cycles: 16, vram_data: 0x01, vram1_data: 0x20)

      normal_first = first_visible_nonzero_pixel(normal)
      xflip_first = first_visible_nonzero_pixel(xflip)

      expect(normal_first).not_to be_nil
      expect(xflip_first).not_to be_nil
      expect(xflip_first).to be < normal_first
    end

    it 'supports background Y-flip via attribute bit 6' do
      reset_video(video)
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)
      normal = sample_mode3(video, cycles: 6, vram_data: 0x01, vram1_data: 0x00)

      reset_video(video)
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)
      yflip = sample_mode3(video, cycles: 6, vram_data: 0x01, vram1_data: 0x40)

      # Tile row offset switches from line 0 (0x10/0x11) to line 7 (0x1E/0x1F).
      expect(normal[2][:vram_addr]).to eq(0x0010)
      expect(normal[4][:vram_addr]).to eq(0x0011)
      expect(yflip[2][:vram_addr]).to eq(0x001E)
      expect(yflip[4][:vram_addr]).to eq(0x001F)
    end

    it 'supports per-tile VRAM bank selection via attribute bit 3' do
      # Keep VRAM0 fixed at 0x01 and toggle attr bit 3 via vram1_data.
      # When bit 3 is set, tile bytes come from VRAM1 instead.
      reset_video(video)
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)
      bank0 = sample_mode3(video, cycles: 16, vram_data: 0x01, vram1_data: 0x00)

      reset_video(video)
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)
      bank1 = sample_mode3(video, cycles: 16, vram_data: 0x01, vram1_data: 0x08)

      bank0_first = first_visible_nonzero_pixel(bank0)
      bank1_first = first_visible_nonzero_pixel(bank1)

      expect(bank0_first).not_to be_nil
      expect(bank1_first).not_to be_nil
      expect(bank1_first).not_to eq(bank0_first)
    end

    it 'supports per-tile palette selection via attribute bits 0-2' do
      reset_video(video)
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)
      seed_cgb_bg_palettes(video)
      pal0 = sample_mode3(video, cycles: 16, vram_data: 0x80, vram1_data: 0x00)

      reset_video(video)
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)
      seed_cgb_bg_palettes(video)
      pal3 = sample_mode3(video, cycles: 16, vram_data: 0x80, vram1_data: 0x03)

      pal0_rgb = first_visible_nonzero_rgb(pal0)
      pal3_rgb = first_visible_nonzero_rgb(pal3)

      expect(pal0_rgb).not_to be_nil
      expect(pal3_rgb).not_to be_nil
      expect(pal3_rgb).not_to eq(pal0_rgb)
    end
  end

  describe 'Sprite Priority' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'handles sprite-to-background priority based on attribute bit 7' do
      capture = lambda do |attr|
        reset_video(video)
        write_video_reg(video, 0x40, 0x93)
        write_video_reg(video, 0x48, 0x00) # OBP0 -> color 0 for visible sprite contrast
        seed_oam_sprite(video, index: 0, y: 16, x: 8, tile: 1, attr: attr)
        advance_to_next_line_start(video)
        sample_mode3_dynamic(video, cycles: 60) { |_addr| [0xFF, 0x00] }
      end

      front = capture.call(0x00)
      behind = capture.call(0x80)
      probe = front.each_index.find do |i|
        front[i][:clkena] == 1 && front[i][:pcnt] >= 9 && front[i][:lcd] == 0
      end

      expect(probe).not_to be_nil
      expect(behind[probe][:lcd]).to eq(3)
    end

    it 'handles GBC OBJ priority mode (FF6C register)' do
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)

      # Write FF6C bit 0
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x6C)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0x01)
      clock_cycle(video)

      # Read FF6C back: upper bits are fixed 1s, bit 0 is writable latch
      video.set_input(:cpu_wr, 0)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0xFF)
    end
  end

  describe 'Window Rendering Edge Cases' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'handles WX=166 window glitch' do
      reset_video(video)
      # Window enabled, dedicated window map selected.
      write_video_reg(video, 0x40, 0xF1)
      write_video_reg(video, 0x4A, 0x00) # WY
      write_video_reg(video, 0x4B, 166)  # WX edge case

      addrs = capture_mode3_vram_addrs(video, cycles: 180)
      first_window = first_window_map_fetch(addrs)

      expect(first_window).not_to be_nil
      expect(first_window).to be >= 150
    end

    it 'handles WX=0 & SCX=7 combined glitch' do
      reset_video(video)
      write_video_reg(video, 0x40, 0xF1)
      write_video_reg(video, 0x4A, 0x00)
      write_video_reg(video, 0x4B, 0x00)
      write_video_reg(video, 0x43, 0x00)
      scx0_addrs = capture_mode3_vram_addrs(video, cycles: 24)
      scx0_first = first_window_map_fetch(scx0_addrs)

      reset_video(video)
      write_video_reg(video, 0x40, 0xF1)
      write_video_reg(video, 0x4A, 0x00)
      write_video_reg(video, 0x4B, 0x00)
      write_video_reg(video, 0x43, 0x07)
      scx7_addrs = capture_mode3_vram_addrs(video, cycles: 24)
      scx7_first = first_window_map_fetch(scx7_addrs)

      expect(scx0_first).not_to be_nil
      expect(scx7_first).not_to be_nil
      expect(scx7_first).to be > scx0_first
    end

    it 'tracks window line counter independently of LY' do
      reset_video(video)
      write_video_reg(video, 0x40, 0xF1)
      write_video_reg(video, 0x4A, 0x00)
      write_video_reg(video, 0x4B, 0x00)

      line0 = sample_one_mode3_line(video, cycles: 12)
      # Change WY after window start; win_line progression should continue
      # from internal counter state rather than re-deriving from LY-WY.
      write_video_reg(video, 0x4A, 0x0A)
      line1 = sample_one_mode3_line(video, cycles: 12)

      line0_window_fetches = line0.count { |addr| addr >= 0x1C00 && addr < 0x2000 }
      line1_window_fetches = line1.count { |addr| addr >= 0x1C00 && addr < 0x2000 }

      line0_data = first_tile_data_fetch(line0)
      line1_data = first_tile_data_fetch(line1)

      expect(line0_window_fetches).to be > 0
      expect(line1_window_fetches).to be > 0
      expect(line0_data).not_to be_nil
      expect(line1_data).not_to be_nil
      # win_line increments by one tile row per active line regardless of WY.
      expect(line1_data).to eq(line0_data + 2)
    end
  end

  describe 'STAT Interrupt Edge Detection' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'triggers STAT interrupt on rising edge only' do
      # Enable LYC STAT source and hold LY==LYC so level stays asserted.
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_addr, 0x45)
      video.set_input(:cpu_di, 0x00)
      clock_cycle(video)
      video.set_input(:cpu_addr, 0x41)
      video.set_input(:cpu_di, 0x40)
      clock_cycle(video)
      video.set_input(:cpu_wr, 0)

      irq_samples = []
      6.times do
        video.propagate
        irq_samples << video.get_output(:irq)
        clock_cycle(video)
      end

      expect(irq_samples.count(1)).to eq(1)
    end

    it 'combines multiple STAT sources correctly (STAT blocking bug)' do
      # Enable OAM + LYC STAT sources while both are active.
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_addr, 0x45)
      video.set_input(:cpu_di, 0x00)
      clock_cycle(video)
      video.set_input(:cpu_addr, 0x41)
      video.set_input(:cpu_di, 0x60)
      clock_cycle(video)
      video.set_input(:cpu_wr, 0)

      initial_samples = []
      4.times do
        video.propagate
        initial_samples << video.get_output(:irq)
        clock_cycle(video)
      end
      expect(initial_samples.count(1)).to eq(1)

      # Clear only LYC match while OAM source remains high in mode 2.
      # Combined STAT level should remain high and must not retrigger.
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_addr, 0x45)
      video.set_input(:cpu_di, 0x01)
      clock_cycle(video)
      video.set_input(:cpu_wr, 0)

      followup_samples = []
      4.times do
        video.propagate
        followup_samples << video.get_output(:irq)
        clock_cycle(video)
      end
      expect(followup_samples.count(1)).to eq(0)
    end
  end

  describe 'DMG STAT Bug' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
      video.set_input(:is_gbc, 0)
      video.set_input(:isGBC_mode, 0)
    end

    it 'mode reads as 0 during transition between VBlank and Mode 2' do
      # Drive internal state to the 1->2 boundary and verify the DMG-only
      # mode=0 readback quirk before normal mode 2 reporting resumes.
      reset_video(video)
      video.set_input(:is_gbc, 0)
      video.set_input(:isGBC_mode, 0)
      video.write_reg(:v_cnt, 0)
      video.write_reg(:h_cnt, 0)
      video.write_reg(:h_div_cnt, 0)
      video.write_reg(:mode_prev, 1)

      video.propagate
      expect(video.get_output(:mode)).to eq(0)

      video.write_reg(:mode_prev, 0)
      video.propagate
      expect(video.get_output(:mode)).to eq(2)
    end
  end

  describe 'GBC Palette Registers' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
      video.set_input(:is_gbc, 1)
      video.set_input(:isGBC_mode, 1)
    end

    it 'auto-increments BGPI/OBPI on palette data write' do
      # BGPI: set index=2 with auto-increment enabled.
      video.set_input(:cpu_sel_reg, 1)
      video.set_input(:cpu_addr, 0x68)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0x82)
      clock_cycle(video)

      # Write BGPD; index should auto-increment to 3.
      video.set_input(:cpu_addr, 0x69)
      video.set_input(:cpu_di, 0x11)
      clock_cycle(video)

      # Read BGPI latch back.
      video.set_input(:cpu_addr, 0x68)
      video.set_input(:cpu_wr, 0)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0xC3)

      # OBPI: set index=4 with auto-increment enabled.
      video.set_input(:cpu_addr, 0x6A)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0x84)
      clock_cycle(video)

      # Write OBPD; index should auto-increment to 5.
      video.set_input(:cpu_addr, 0x6B)
      video.set_input(:cpu_di, 0x22)
      clock_cycle(video)

      video.set_input(:cpu_addr, 0x6A)
      video.set_input(:cpu_wr, 0)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0xC5)
    end

    it 'reads correct palette data from BGPD (FF69)' do
      video.set_input(:cpu_sel_reg, 1)

      # Select BG palette index 5 (no auto-inc), then write/read FF69.
      video.set_input(:cpu_addr, 0x68)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0x05)
      clock_cycle(video)

      video.set_input(:cpu_addr, 0x69)
      video.set_input(:cpu_di, 0xAB)
      clock_cycle(video)

      video.set_input(:cpu_wr, 0)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0xAB)
    end

    it 'reads correct palette data from OBPD (FF6B)' do
      video.set_input(:cpu_sel_reg, 1)

      # Select OBJ palette index 9 (no auto-inc), then write/read FF6B.
      video.set_input(:cpu_addr, 0x6A)
      video.set_input(:cpu_wr, 1)
      video.set_input(:cpu_di, 0x09)
      clock_cycle(video)

      video.set_input(:cpu_addr, 0x6B)
      video.set_input(:cpu_di, 0xCD)
      clock_cycle(video)

      video.set_input(:cpu_wr, 0)
      video.propagate
      expect(video.get_output(:cpu_do)).to eq(0xCD)
    end
  end

  describe 'Mode 3 Variable Length' do
    before do
      video.set_input(:reset, 1)
      clock_cycle(video)
      video.set_input(:reset, 0)
      clock_cycle(video)
    end

    it 'mode 3 length varies based on sprite count' do
      reset_video(video)
      write_video_reg(video, 0x40, 0x91) # Sprites disabled
      no_sprites = measure_mode3_length(video)

      reset_video(video)
      write_video_reg(video, 0x40, 0x93) # Sprites enabled
      video.set_input(:extra_spr_en, 0)
      sprites_on = measure_mode3_length(video)

      reset_video(video)
      write_video_reg(video, 0x40, 0x93)
      video.set_input(:extra_spr_en, 1)
      extra_sprites = measure_mode3_length(video)

      expect(sprites_on).to be > no_sprites
      expect(extra_sprites).to be > sprites_on
    end

    it 'mode 3 length affected by window first fetch' do
      reset_video(video)
      write_video_reg(video, 0x40, 0x91) # Window disabled
      window_off = measure_mode3_length(video)

      reset_video(video)
      write_video_reg(video, 0x40, 0xB1) # Window enabled
      write_video_reg(video, 0x4A, 0x00) # WY
      write_video_reg(video, 0x4B, 0x00) # WX
      window_on = measure_mode3_length(video)

      expect(window_on).to be > window_off
    end

    it 'mode 3 length affected by SCX fine scroll' do
      reset_video(video)
      write_video_reg(video, 0x43, 0x00) # SCX fine scroll = 0
      scx0 = measure_mode3_length(video)

      reset_video(video)
      write_video_reg(video, 0x43, 0x07) # SCX fine scroll = 7
      scx7 = measure_mode3_length(video)

      expect(scx7).to be > scx0
    end
  end
end
