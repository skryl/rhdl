# frozen_string_literal: true

# Apple II Hi-Res Color Renderer
# Renders Apple II hi-res screen with NTSC artifact colors
#
# The Apple II produces color through NTSC artifact coloring:
# - Pixels at 7.16 MHz (2x NTSC colorburst at 3.58 MHz)
# - Adjacent pixels of different phases produce colors
# - Bit 7 of each byte selects between two color palettes:
#   - Palette 0 (bit7=0): Black, Green, Purple, White
#   - Palette 1 (bit7=1): Black, Orange, Blue, White

module RHDL
  module Apple2
    # Renders Apple II hi-res graphics with NTSC artifact colors
    # Uses 3-bit sliding window algorithm for color determination
    class ColorRenderer
      HIRES_WIDTH = 280   # pixels
      HIRES_HEIGHT = 192  # lines
      HIRES_BYTES_PER_LINE = 40

      # ANSI escape codes
      ESC = "\e"
      NORMAL_VIDEO = "#{ESC}[0m"

      # HiRes color palette (RGB values)
      # These values are commonly used in Apple II emulators
      COLORS = {
        black:  [0x00, 0x00, 0x00],
        white:  [0xFF, 0xFF, 0xFF],
        green:  [0x14, 0xF5, 0x3C],  # NTSC artifact green
        purple: [0xD6, 0x60, 0xEF],  # NTSC artifact purple/violet
        orange: [0xFF, 0x6A, 0x3C],  # NTSC artifact orange
        blue:   [0x14, 0xCF, 0xFD]   # NTSC artifact blue
      }.freeze

      # Half-block characters for rendering
      UPPER_HALF = "\u2580"  # Upper half block
      LOWER_HALF = "\u2584"  # Lower half block
      FULL_BLOCK = "\u2588"  # Full block

      def initialize(options = {})
        @chars_wide = options[:chars_wide] || 140
      end

      # Render hi-res memory to colored string
      # ram: memory array with hi-res data
      # base_addr: base address of hi-res page (0x2000 for page 1)
      # Returns multi-line string with ANSI color codes
      def render(ram, base_addr: 0x2000, chars_wide: @chars_wide)
        # First, decode the bitmap with color information
        color_bitmap = decode_hires_colors(ram, base_addr)

        # Render using half-block characters (2 rows per character)
        render_half_blocks(color_bitmap, chars_wide)
      end

      # Decode hi-res memory into a color bitmap
      # Returns 2D array of color symbols (192 rows x 280 pixels)
      def decode_hires_colors(ram, base_addr)
        bitmap = []

        HIRES_HEIGHT.times do |row|
          line = []
          line_addr = hires_line_address(row, base_addr)

          # Process each byte in the line
          HIRES_BYTES_PER_LINE.times do |col|
            byte = ram[line_addr + col] || 0
            high_bit = (byte >> 7) & 1  # Palette select

            # Get previous byte's last pixel for sliding window
            prev_byte = col > 0 ? (ram[line_addr + col - 1] || 0) : 0
            prev_pixel = (prev_byte >> 6) & 1

            # Get next byte's first pixel for sliding window
            next_byte = col < HIRES_BYTES_PER_LINE - 1 ? (ram[line_addr + col + 1] || 0) : 0
            next_first = next_byte & 1

            # Process 7 pixels in this byte
            7.times do |bit|
              curr_pixel = (byte >> bit) & 1

              # Get adjacent pixels for the 3-bit window
              if bit == 0
                prev = prev_pixel
              else
                prev = (byte >> (bit - 1)) & 1
              end

              if bit == 6
                nxt = next_first
              else
                nxt = (byte >> (bit + 1)) & 1
              end

              # Determine color from 3-bit pattern
              color = determine_color(prev, curr_pixel, nxt, high_bit, col * 7 + bit)
              line << color
            end
          end

          bitmap << line
        end

        bitmap
      end

      # Determine pixel color using 3-bit sliding window algorithm
      # prev: previous pixel (0/1)
      # curr: current pixel (0/1)
      # nxt: next pixel (0/1)
      # high_bit: palette select (0 = green/purple, 1 = blue/orange)
      # x_pos: horizontal position (for odd/even determination)
      def determine_color(prev, curr, nxt, high_bit, x_pos)
        pattern = (prev << 2) | (curr << 1) | nxt

        case pattern
        when 0b000, 0b001, 0b100
          # No current pixel lit, or isolated edges -> black
          :black
        when 0b011, 0b110, 0b111
          # Current pixel with neighbor(s) -> white
          :white
        when 0b010
          # Isolated pixel - color depends on position and palette
          if high_bit == 0
            x_pos.odd? ? :green : :purple
          else
            x_pos.odd? ? :orange : :blue
          end
        when 0b101
          # Gap between two pixels - creates artifact color
          if high_bit == 0
            x_pos.odd? ? :purple : :green
          else
            x_pos.odd? ? :blue : :orange
          end
        else
          :black
        end
      end

      # Render color bitmap using half-block characters
      # Each terminal character shows 2 vertical pixels
      def render_half_blocks(color_bitmap, chars_wide)
        output = String.new

        # Scale factor for horizontal
        x_scale = HIRES_WIDTH.to_f / chars_wide

        # Process 2 rows at a time (upper/lower half blocks)
        (HIRES_HEIGHT / 2).times do |char_row|
          upper_row = char_row * 2
          lower_row = char_row * 2 + 1

          chars_wide.times do |char_col|
            # Sample pixel at this position
            px = (char_col * x_scale).to_i
            px = [px, HIRES_WIDTH - 1].min

            upper_color = color_bitmap[upper_row][px]
            lower_color = color_bitmap[lower_row][px]

            # Generate character with appropriate colors
            output << color_char(upper_color, lower_color)
          end

          output << NORMAL_VIDEO << "\n"
        end

        output
      end

      # Generate a colored character for upper/lower pixel colors
      def color_char(upper_color, lower_color)
        upper_rgb = COLORS[upper_color]
        lower_rgb = COLORS[lower_color]

        if upper_color == lower_color
          # Same color - use full block or space
          if upper_color == :black
            NORMAL_VIDEO + " "
          else
            fg_color(upper_rgb) + FULL_BLOCK
          end
        elsif upper_color == :black
          # Only lower pixel lit - need bg black to avoid bleed
          fg_color(lower_rgb) + bg_color(COLORS[:black]) + LOWER_HALF
        elsif lower_color == :black
          # Only upper pixel lit - need bg black to avoid bleed
          fg_color(upper_rgb) + bg_color(COLORS[:black]) + UPPER_HALF
        else
          # Both different colors - use upper half with fg/bg
          fg_color(upper_rgb) + bg_color(lower_rgb) + UPPER_HALF
        end
      end

      # ANSI truecolor foreground escape sequence
      def fg_color(rgb)
        "#{ESC}[38;2;#{rgb[0]};#{rgb[1]};#{rgb[2]}m"
      end

      # ANSI truecolor background escape sequence
      def bg_color(rgb)
        "#{ESC}[48;2;#{rgb[0]};#{rgb[1]};#{rgb[2]}m"
      end

      # Hi-res screen line address calculation (Apple II interleaved layout)
      def hires_line_address(row, base)
        # Each group of 8 consecutive rows is separated by 0x400 bytes
        # Groups of 8 lines within a section are 0x80 apart
        # Sections (0-63, 64-127, 128-191) are 0x28 apart
        section = row / 64           # 0, 1, or 2
        row_in_section = row % 64
        group = row_in_section / 8   # 0-7
        line_in_group = row_in_section % 8  # 0-7

        base + (line_in_group * 0x400) + (group * 0x80) + (section * 0x28)
      end

      # Render to array of lines
      def render_lines(ram, base_addr: 0x2000, chars_wide: @chars_wide)
        render(ram, base_addr: base_addr, chars_wide: chars_wide).split("\n")
      end

      # Class method for quick rendering
      def self.render(ram, base_addr: 0x2000, chars_wide: 140)
        new(chars_wide: chars_wide).render(ram, base_addr: base_addr)
      end
    end
  end
end
