# Game Boy LCD Controller
# Corresponds to: reference/rtl/lcd.v
#
# Handles LCD timing and signal generation for display output.
# This module is primarily for MiSTer FPGA output formatting.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module GameBoy
      class LCD < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # Display specifications:
    # - 160x144 active pixels
    # - 456 dots per line (including HBlank)
    # - 154 lines per frame (including VBlank)
    # - 59.7275 Hz frame rate

    SCREEN_WIDTH = 160
    SCREEN_HEIGHT = 144
    DOTS_PER_LINE = 456
    LINES_PER_FRAME = 154

    input :clk
    input :ce
    input :reset

    input :lcd_on          # LCD enable
    input :is_gbc           # Game Boy Color mode

    # Pixel input from PPU
    input :pixel_data, width: 15   # RGB555
    input :pixel_valid             # Pixel valid strobe

    # LCD output signals
    output :lcd_clk        # Pixel clock
    output :lcd_de         # Data enable (active during visible area)
    output :lcd_hsync      # Horizontal sync
    output :lcd_vsync      # Vertical sync
    output :lcd_r, width: 5
    output :lcd_g, width: 5
    output :lcd_b, width: 5

    # Internal counters
    wire :h_counter, width: 9   # 0-455
    wire :v_counter, width: 8   # 0-153
    wire :visible_area

    behavior do
      # Visible area detection
      visible_area <= lcd_on &
                      (h_counter < lit(SCREEN_WIDTH, width: 9)) &
                      (v_counter < lit(SCREEN_HEIGHT, width: 8))

      # Output signals
      lcd_de <= visible_area
      lcd_clk <= ce

      # Sync signals (active low)
      lcd_hsync <= ~(h_counter >= lit(SCREEN_WIDTH + 8, width: 9)) &
                   (h_counter < lit(SCREEN_WIDTH + 8 + 32, width: 9))
      lcd_vsync <= ~(v_counter >= lit(SCREEN_HEIGHT + 1, width: 8)) &
                   (v_counter < lit(SCREEN_HEIGHT + 1 + 4, width: 8))

      # RGB output
      lcd_r <= mux(visible_area, pixel_data[4..0], lit(0, width: 5))
      lcd_g <= mux(visible_area, pixel_data[9..5], lit(0, width: 5))
      lcd_b <= mux(visible_area, pixel_data[14..10], lit(0, width: 5))
    end

    sequential clock: :clk, reset: :reset, reset_values: {
      h_counter: 0,
      v_counter: 0
    } do
      # Horizontal counter
      h_counter <= mux(ce & lcd_on,
                       mux(h_counter == lit(DOTS_PER_LINE - 1, width: 9),
                           lit(0, width: 9),
                           h_counter + lit(1, width: 9)),
                       h_counter)

      # Vertical counter
      v_counter <= mux(ce & lcd_on & (h_counter == lit(DOTS_PER_LINE - 1, width: 9)),
                       mux(v_counter == lit(LINES_PER_FRAME - 1, width: 8),
                           lit(0, width: 8),
                           v_counter + lit(1, width: 8)),
                       v_counter)

      # Reset counters when LCD is turned off
      h_counter <= mux(~lcd_on, lit(0, width: 9), h_counter)
      v_counter <= mux(~lcd_on, lit(0, width: 8), v_counter)
    end
      end
    end
  end
end
