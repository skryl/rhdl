# frozen_string_literal: true

# Apple II Hi-Res Braille Renderer
# Renders Apple II hi-res screen using Unicode braille characters (2x4 dots per char)

module RHDL
  module Apple2
    # Renders Apple II hi-res graphics using Unicode braille characters
    # Each braille character is 2 dots wide x 4 dots tall, providing
    # high-resolution monochrome display in terminal
    class BrailleRenderer
      HIRES_WIDTH = 280   # pixels
      HIRES_HEIGHT = 192  # lines

      # ANSI escape codes
      ESC = "\e"
      GREEN_FG = "#{ESC}[32m"
      BLACK_BG = "#{ESC}[40m"
      NORMAL_VIDEO = "#{ESC}[0m"

      # Braille dot positions (Unicode mapping):
      # Dot 1 (0x01) Dot 4 (0x08)
      # Dot 2 (0x02) Dot 5 (0x10)
      # Dot 3 (0x04) Dot 6 (0x20)
      # Dot 7 (0x40) Dot 8 (0x80)
      DOT_MAP = [
        [0x01, 0x08],  # row 0
        [0x02, 0x10],  # row 1
        [0x04, 0x20],  # row 2
        [0x40, 0x80]   # row 3
      ].freeze

      def initialize(options = {})
        @green_screen = options[:green] || false
        @invert = options[:invert] || false
        @chars_wide = options[:chars_wide] || 80
      end

      # Render hi-res bitmap to braille string
      # bitmap: 2D array of 0/1 values (192 rows x 280 pixels)
      # Returns multi-line string of braille characters
      def render(bitmap, chars_wide: @chars_wide, invert: @invert)
        # Braille characters are 2 dots wide x 4 dots tall
        chars_tall = (HIRES_HEIGHT / 4.0).ceil

        # Scale factors
        x_scale = HIRES_WIDTH.to_f / (chars_wide * 2)
        y_scale = HIRES_HEIGHT.to_f / (chars_tall * 4)

        output = String.new
        output << GREEN_FG << BLACK_BG if @green_screen

        lines = []
        chars_tall.times do |char_y|
          line = String.new
          chars_wide.times do |char_x|
            pattern = 0

            # Sample 2x4 grid for this braille character
            4.times do |dy|
              2.times do |dx|
                px = ((char_x * 2 + dx) * x_scale).to_i
                py = ((char_y * 4 + dy) * y_scale).to_i
                px = [px, HIRES_WIDTH - 1].min
                py = [py, HIRES_HEIGHT - 1].min

                pixel = bitmap[py][px]
                pixel = 1 - pixel if invert
                pattern |= DOT_MAP[dy][dx] if pixel == 1
              end
            end

            # Unicode braille starts at U+2800
            line << (0x2800 + pattern).chr(Encoding::UTF_8)
          end
          lines << line
        end

        output << lines.join("\n")
        output << NORMAL_VIDEO if @green_screen

        output
      end

      # Render to array of lines (without newlines)
      def render_lines(bitmap, chars_wide: @chars_wide, invert: @invert)
        render(bitmap, chars_wide: chars_wide, invert: invert).split("\n")
      end
    end
  end
end
