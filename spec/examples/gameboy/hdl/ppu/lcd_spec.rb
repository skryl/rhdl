# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/gameboy/gameboy'

# Game Boy LCD Controller Component Tests
# Tests the LCD controller which handles:
# - LCD timing and signal generation
# - 160x144 pixel display output
# - Horizontal and vertical sync signals
# - RGB pixel output
#
# Display specifications:
# - 160x144 active pixels
# - 456 dots per line (including HBlank)
# - 154 lines per frame (including VBlank)
# - 59.7275 Hz frame rate
RSpec.describe GameBoy::LCD do
  # Display constants (matching lcd.rb)
  SCREEN_WIDTH = 160
  SCREEN_HEIGHT = 144
  DOTS_PER_LINE = 456
  LINES_PER_FRAME = 154

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

  let(:lcd) { GameBoy::LCD.new }

  before do
    # Initialize inputs to default values
    lcd.set_input(:clk, 0)
    lcd.set_input(:ce, 1)
    lcd.set_input(:reset, 0)
    lcd.set_input(:lcd_on, 1)       # LCD enabled
    lcd.set_input(:is_gbc, 0)       # DMG mode
    lcd.set_input(:pixel_data, 0)   # Black pixel
    lcd.set_input(:pixel_valid, 0)  # No valid pixel
    lcd.propagate
  end

  describe 'component instantiation' do
    it 'creates an LCD component' do
      expect(lcd).to be_a(GameBoy::LCD)
    end

    it 'has LCD timing outputs' do
      expect { lcd.get_output(:lcd_clk) }.not_to raise_error
      expect { lcd.get_output(:lcd_de) }.not_to raise_error
      expect { lcd.get_output(:lcd_hsync) }.not_to raise_error
      expect { lcd.get_output(:lcd_vsync) }.not_to raise_error
    end

    it 'has RGB color outputs' do
      expect { lcd.get_output(:lcd_r) }.not_to raise_error
      expect { lcd.get_output(:lcd_g) }.not_to raise_error
      expect { lcd.get_output(:lcd_b) }.not_to raise_error
    end
  end

  describe 'reset behavior' do
    it 'resets counters to zero' do
      # Run some cycles first
      clock_cycles(lcd, 50)

      # Apply reset
      lcd.set_input(:reset, 1)
      clock_cycle(lcd)

      # Counters should be reset to 0
      # This manifests in the visible_area and sync signals
      lcd.set_input(:reset, 0)
      lcd.propagate

      # At h_counter=0, v_counter=0, should be in visible area
      expect(lcd.get_output(:lcd_de)).to eq(1)  # Data enable
    end
  end

  describe 'horizontal counter' do
    before do
      lcd.set_input(:reset, 1)
      clock_cycle(lcd)
      lcd.set_input(:reset, 0)
      clock_cycle(lcd)
    end

    it 'starts at zero after reset' do
      # At position 0, should be in visible area
      expect(lcd.get_output(:lcd_de)).to eq(1)
    end

    it 'counts through visible area (0-159)' do
      # Run through part of visible width (not all to avoid timeout)
      clock_cycles(lcd, 50)

      # Should still be in visible area
      expect(lcd.get_output(:lcd_de)).to eq(1)
    end

    it 'enters HBlank after visible area', :slow do
      # Advance past visible area
      clock_cycles(lcd, SCREEN_WIDTH)

      # Should be in HBlank (lcd_de = 0)
      expect(lcd.get_output(:lcd_de)).to eq(0)
    end

    it 'wraps after DOTS_PER_LINE cycles', :slow do
      # Complete one line
      clock_cycles(lcd, DOTS_PER_LINE)

      # Should be back at start of visible area
      expect(lcd.get_output(:lcd_de)).to eq(1)
    end
  end

  describe 'vertical counter' do
    before do
      lcd.set_input(:reset, 1)
      clock_cycle(lcd)
      lcd.set_input(:reset, 0)
      clock_cycle(lcd)
    end

    it 'increments after each scanline', :slow do
      # Run one complete line
      clock_cycles(lcd, DOTS_PER_LINE)

      # Should be on line 1, still visible
      expect(lcd.get_output(:lcd_de)).to eq(1)
    end

    it 'enters VBlank at line 144', :slow do
      # Run through all visible lines
      clock_cycles(lcd, DOTS_PER_LINE * SCREEN_HEIGHT)

      # At start of line 144, should be in VBlank
      expect(lcd.get_output(:lcd_de)).to eq(0)
    end

    it 'completes frame after LINES_PER_FRAME scanlines', :slow do
      # Run complete frame
      clock_cycles(lcd, DOTS_PER_LINE * LINES_PER_FRAME)

      # Should be back at line 0
      expect(lcd.get_output(:lcd_de)).to eq(1)
    end
  end

  describe 'visible area detection' do
    before do
      lcd.set_input(:reset, 1)
      clock_cycle(lcd)
      lcd.set_input(:reset, 0)
      clock_cycle(lcd)
    end

    it 'asserts lcd_de during visible area' do
      expect(lcd.get_output(:lcd_de)).to eq(1)
    end

    it 'deasserts lcd_de during HBlank', :slow do
      clock_cycles(lcd, SCREEN_WIDTH)
      expect(lcd.get_output(:lcd_de)).to eq(0)
    end

    it 'deasserts lcd_de during VBlank', :slow do
      clock_cycles(lcd, DOTS_PER_LINE * SCREEN_HEIGHT)
      expect(lcd.get_output(:lcd_de)).to eq(0)
    end

    it 'depends on lcd_on being enabled' do
      lcd.set_input(:lcd_on, 0)
      lcd.propagate

      # With LCD off, visible area should be 0
      expect(lcd.get_output(:lcd_de)).to eq(0)
    end
  end

  describe 'horizontal sync' do
    before do
      lcd.set_input(:reset, 1)
      clock_cycle(lcd)
      lcd.set_input(:reset, 0)
      clock_cycle(lcd)
    end

    it 'generates HSYNC pulse during HBlank', :slow do
      # HSYNC active (low) from pixel SCREEN_WIDTH+8 to SCREEN_WIDTH+8+32
      # Run to HSYNC start
      clock_cycles(lcd, SCREEN_WIDTH + 8)

      hsync = lcd.get_output(:lcd_hsync)
      # HSYNC is active low
      expect(hsync).to eq(0)
    end

    it 'HSYNC is inactive during visible area' do
      expect(lcd.get_output(:lcd_hsync)).to eq(1)
    end
  end

  describe 'vertical sync' do
    before do
      lcd.set_input(:reset, 1)
      clock_cycle(lcd)
      lcd.set_input(:reset, 0)
      clock_cycle(lcd)
    end

    it 'generates VSYNC pulse at start of VBlank', :slow do
      # Run to start of VBlank (line 144)
      clock_cycles(lcd, DOTS_PER_LINE * SCREEN_HEIGHT)

      # VSYNC active at lines 145-148 (SCREEN_HEIGHT+1 to SCREEN_HEIGHT+4)
      clock_cycles(lcd, DOTS_PER_LINE)  # Line 145

      vsync = lcd.get_output(:lcd_vsync)
      expect(vsync).to eq(0)  # Active low
    end

    it 'VSYNC is inactive during visible lines' do
      expect(lcd.get_output(:lcd_vsync)).to eq(1)
    end
  end

  describe 'RGB output' do
    before do
      lcd.set_input(:reset, 1)
      clock_cycle(lcd)
      lcd.set_input(:reset, 0)
      clock_cycle(lcd)
    end

    it 'outputs pixel data during visible area' do
      # Set RGB555 pixel data (white = 0x7FFF)
      lcd.set_input(:pixel_data, 0x7FFF)
      lcd.propagate

      # In visible area, should output the pixel data
      expect(lcd.get_output(:lcd_r)).to eq(0x1F)  # bits 0-4
      expect(lcd.get_output(:lcd_g)).to eq(0x1F)  # bits 5-9
      expect(lcd.get_output(:lcd_b)).to eq(0x1F)  # bits 10-14
    end

    it 'outputs black when LCD is off' do
      lcd.set_input(:pixel_data, 0x7FFF)
      lcd.set_input(:lcd_on, 0)
      lcd.propagate

      # When LCD is off, visible_area is 0, so outputs should be black
      expect(lcd.get_output(:lcd_r)).to eq(0)
      expect(lcd.get_output(:lcd_g)).to eq(0)
      expect(lcd.get_output(:lcd_b)).to eq(0)
    end

    it 'outputs black during HBlank', :slow do
      lcd.set_input(:pixel_data, 0x7FFF)
      clock_cycles(lcd, SCREEN_WIDTH)

      # In HBlank, should output black (0)
      lcd.propagate
      expect(lcd.get_output(:lcd_r)).to eq(0)
      expect(lcd.get_output(:lcd_g)).to eq(0)
      expect(lcd.get_output(:lcd_b)).to eq(0)
    end

    it 'outputs black during VBlank', :slow do
      lcd.set_input(:pixel_data, 0x7FFF)
      clock_cycles(lcd, DOTS_PER_LINE * SCREEN_HEIGHT)

      lcd.propagate
      expect(lcd.get_output(:lcd_r)).to eq(0)
      expect(lcd.get_output(:lcd_g)).to eq(0)
      expect(lcd.get_output(:lcd_b)).to eq(0)
    end

    it 'extracts R, G, B components correctly' do
      # Set a specific RGB555 value: R=10, G=15, B=20
      # Format: BBBBB_GGGGG_RRRRR
      rgb = (20 << 10) | (15 << 5) | 10
      lcd.set_input(:pixel_data, rgb)
      lcd.propagate

      expect(lcd.get_output(:lcd_r)).to eq(10)
      expect(lcd.get_output(:lcd_g)).to eq(15)
      expect(lcd.get_output(:lcd_b)).to eq(20)
    end
  end

  describe 'clock enable' do
    before do
      lcd.set_input(:reset, 1)
      clock_cycle(lcd)
      lcd.set_input(:reset, 0)
      clock_cycle(lcd)
    end

    it 'only advances counters when ce is high' do
      initial_de = lcd.get_output(:lcd_de)

      # Run without ce
      clock_cycles(lcd, 10, enable_ce: false)
      lcd.propagate

      # Should still be at same position
      expect(lcd.get_output(:lcd_de)).to eq(initial_de)
    end

    it 'lcd_clk follows ce signal' do
      lcd.set_input(:ce, 1)
      lcd.propagate
      expect(lcd.get_output(:lcd_clk)).to eq(1)

      lcd.set_input(:ce, 0)
      lcd.propagate
      expect(lcd.get_output(:lcd_clk)).to eq(0)
    end
  end

  describe 'LCD disable' do
    before do
      lcd.set_input(:reset, 1)
      clock_cycle(lcd)
      lcd.set_input(:reset, 0)
      clock_cycle(lcd)
    end

    it 'resets counters when LCD is disabled' do
      # Run some cycles
      clock_cycles(lcd, 50)

      # Disable LCD
      lcd.set_input(:lcd_on, 0)
      clock_cycle(lcd)

      # Counters should reset
      lcd.propagate
      expect(lcd.get_output(:lcd_de)).to eq(0)
    end

    it 'stops counting when LCD is disabled' do
      lcd.set_input(:lcd_on, 0)
      clock_cycles(lcd, 50)

      # Should remain in reset state
      expect(lcd.get_output(:lcd_de)).to eq(0)
    end
  end

  describe 'Game Boy Color mode' do
    it 'accepts is_gbc input' do
      lcd.set_input(:is_gbc, 1)
      lcd.propagate

      # Component should accept the input without error
    end
  end

  describe 'frame timing', :slow do
    before do
      lcd.set_input(:reset, 1)
      clock_cycle(lcd)
      lcd.set_input(:reset, 0)
      clock_cycle(lcd)
    end

    it 'completes a frame in correct number of cycles' do
      cycles_per_frame = DOTS_PER_LINE * LINES_PER_FRAME

      # Run one complete frame
      clock_cycles(lcd, cycles_per_frame)

      # Should be back at start
      expect(lcd.get_output(:lcd_de)).to eq(1)
    end

    it 'has correct visible area dimensions' do
      visible_count = 0

      # Count visible pixels in one line
      DOTS_PER_LINE.times do
        visible_count += 1 if lcd.get_output(:lcd_de) == 1
        clock_cycle(lcd)
      end

      expect(visible_count).to eq(SCREEN_WIDTH)
    end

    it 'has correct number of visible lines' do
      visible_lines = 0

      LINES_PER_FRAME.times do |line|
        # Check at start of each line
        visible_lines += 1 if lcd.get_output(:lcd_de) == 1
        clock_cycles(lcd, DOTS_PER_LINE)
      end

      expect(visible_lines).to eq(SCREEN_HEIGHT)
    end
  end

  describe 'pixel data passthrough' do
    before do
      lcd.set_input(:reset, 1)
      clock_cycle(lcd)
      lcd.set_input(:reset, 0)
      clock_cycle(lcd)
    end

    it 'passes through varying pixel values' do
      test_values = [0x0000, 0x7FFF, 0x5555, 0x2AAA, 0x1234]

      test_values.each do |value|
        lcd.set_input(:pixel_data, value)
        lcd.propagate

        expected_r = value & 0x1F
        expected_g = (value >> 5) & 0x1F
        expected_b = (value >> 10) & 0x1F

        expect(lcd.get_output(:lcd_r)).to eq(expected_r), "Failed for value 0x#{value.to_s(16)}"
        expect(lcd.get_output(:lcd_g)).to eq(expected_g), "Failed for value 0x#{value.to_s(16)}"
        expect(lcd.get_output(:lcd_b)).to eq(expected_b), "Failed for value 0x#{value.to_s(16)}"
      end
    end
  end
end
