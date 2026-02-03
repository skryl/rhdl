# frozen_string_literal: true

# Game Boy LCD Renderer
# Renders the Game Boy screen (160x144) using various terminal formats

module RHDL
  module GameBoy
    # LCD renderer for Game Boy display
    # Supports braille characters for high-resolution terminal output
    class LcdRenderer
      # Game Boy screen dimensions
      SCREEN_WIDTH = 160
      SCREEN_HEIGHT = 144

      # Game Boy color palette (DMG green shades)
      DMG_COLORS = [
        [155, 188, 15],   # Lightest (off)
        [139, 172, 15],   # Light
        [48, 98, 48],     # Dark
        [15, 56, 15]      # Darkest (on)
      ].freeze

      # ANSI color codes for the DMG palette
      DMG_ANSI = [
        "\e[38;2;155;188;15m",   # Lightest
        "\e[38;2;139;172;15m",   # Light
        "\e[38;2;48;98;48m",     # Dark
        "\e[38;2;15;56;15m"      # Darkest
      ].freeze

      RESET = "\e[0m"

      # @param chars_wide [Integer] Target width in characters
      # @param invert [Boolean] Invert colors (light on dark)
      def initialize(chars_wide: 80, invert: false)
        @chars_wide = chars_wide
        @invert = invert
      end

      # Render framebuffer using Unicode braille characters (2x4 dots per char)
      # @param framebuffer [Array<Array<Integer>>] 2D array of 2-bit color values
      # @return [String] Rendered output
      def render_braille(framebuffer)
        return empty_screen if framebuffer.nil? || framebuffer.empty?

        # Calculate dimensions
        chars_tall = (SCREEN_HEIGHT / 4.0).ceil
        x_scale = SCREEN_WIDTH.to_f / (@chars_wide * 2)
        y_scale = SCREEN_HEIGHT.to_f / (chars_tall * 4)

        # Braille dot mapping (2x4 grid -> Unicode braille)
        # Pattern bits: 1  8
        #              2  16
        #              4  32
        #              64 128
        dot_map = [
          [0x01, 0x08],
          [0x02, 0x10],
          [0x04, 0x20],
          [0x40, 0x80]
        ]

        lines = []
        chars_tall.times do |char_y|
          line = String.new
          @chars_wide.times do |char_x|
            pattern = 0

            4.times do |dy|
              2.times do |dx|
                px = ((char_x * 2 + dx) * x_scale).to_i
                py = ((char_y * 4 + dy) * y_scale).to_i
                px = [px, SCREEN_WIDTH - 1].min
                py = [py, SCREEN_HEIGHT - 1].min

                # Get pixel value (0-3)
                pixel = framebuffer[py][px] rescue 0

                # Convert to on/off based on threshold
                # Darker colors (2, 3) are "on"
                is_on = pixel >= 2
                is_on = !is_on if @invert

                pattern |= dot_map[dy][dx] if is_on
              end
            end

            line << (0x2800 + pattern).chr(Encoding::UTF_8)
          end
          lines << line
        end

        lines.join("\n")
      end

      # Render framebuffer using half-block characters for color output
      # @param framebuffer [Array<Array<Integer>>] 2D array of 2-bit color values
      # @return [String] Rendered output with ANSI colors
      def render_color(framebuffer)
        return empty_color_screen if framebuffer.nil? || framebuffer.empty?

        # Each char represents 2 vertical pixels using half-blocks
        chars_tall = (SCREEN_HEIGHT / 2.0).ceil
        x_scale = SCREEN_WIDTH.to_f / @chars_wide
        y_scale = SCREEN_HEIGHT.to_f / (chars_tall * 2)

        lines = []
        chars_tall.times do |char_y|
          line = String.new
          @chars_wide.times do |char_x|
            px = (char_x * x_scale).to_i
            py_top = ((char_y * 2) * y_scale / 2).to_i
            py_bot = ((char_y * 2 + 1) * y_scale / 2).to_i

            px = [px, SCREEN_WIDTH - 1].min
            py_top = [py_top, SCREEN_HEIGHT - 1].min
            py_bot = [py_bot, SCREEN_HEIGHT - 1].min

            top_color = framebuffer[py_top][px] rescue 0
            bot_color = framebuffer[py_bot][px] rescue 0

            top_color = 3 - top_color if @invert
            bot_color = 3 - bot_color if @invert

            # Use half-block characters with foreground/background colors
            top_rgb = DMG_COLORS[top_color]
            bot_rgb = DMG_COLORS[bot_color]

            # Upper half block with top color as fg, bottom color as bg
            fg = "\e[38;2;#{top_rgb[0]};#{top_rgb[1]};#{top_rgb[2]}m"
            bg = "\e[48;2;#{bot_rgb[0]};#{bot_rgb[1]};#{bot_rgb[2]}m"
            line << fg << bg << "\u2580"
          end
          lines << (line + RESET)
        end

        lines.join("\n")
      end

      # Render framebuffer as ASCII art
      # @param framebuffer [Array<Array<Integer>>] 2D array of 2-bit color values
      # @return [String] Rendered output
      def render_ascii(framebuffer)
        return empty_screen if framebuffer.nil? || framebuffer.empty?

        # ASCII shading characters (light to dark)
        shades = @invert ? [' ', '.', 'o', '#'] : ['#', 'o', '.', ' ']

        chars_tall = (SCREEN_HEIGHT.to_f / 2).ceil
        x_scale = SCREEN_WIDTH.to_f / @chars_wide
        y_scale = SCREEN_HEIGHT.to_f / chars_tall

        lines = []
        chars_tall.times do |char_y|
          line = String.new
          @chars_wide.times do |char_x|
            px = (char_x * x_scale).to_i
            py = (char_y * y_scale).to_i
            px = [px, SCREEN_WIDTH - 1].min
            py = [py, SCREEN_HEIGHT - 1].min

            pixel = framebuffer[py][px] rescue 0
            line << shades[pixel & 3]
          end
          lines << line
        end

        lines.join("\n")
      end

      # Create a bordered frame for the LCD output
      # @param content [String] The rendered LCD content
      # @param title [String] Optional title for the frame
      # @return [String] Framed content
      def frame(content, title: nil)
        lines = content.split("\n")
        content_width = lines.map { |l| l.gsub(/\e\[[0-9;]*m/, '').length }.max || @chars_wide

        # Ensure frame is wide enough for title
        title_width = title ? title.length + 4 : 0  # +4 for " title " and spaces
        max_width = [content_width, title_width].max

        output = String.new
        if title
          padding = [(max_width - title.length - 2) / 2, 0].max
          right_padding = [max_width - padding - title.length - 2, 0].max
          output << "+" << ("-" * padding) << " #{title} " << ("-" * right_padding) << "+\n"
        else
          output << "+" << ("-" * max_width) << "+\n"
        end

        lines.each do |line|
          visible_length = line.gsub(/\e\[[0-9;]*m/, '').length
          padding = [max_width - visible_length, 0].max
          output << "|" << line << (" " * padding) << "|\n"
        end

        output << "+" << ("-" * max_width) << "+"
        output
      end

      private

      def empty_screen
        lines = []
        chars_tall = (SCREEN_HEIGHT / 4.0).ceil
        chars_tall.times do
          lines << ("\u2800" * @chars_wide)
        end
        lines.join("\n")
      end

      def empty_color_screen
        # Show empty screen with lightest DMG color (off state)
        lines = []
        chars_tall = (SCREEN_HEIGHT / 2.0).ceil
        bg_rgb = DMG_COLORS[0]  # Lightest color
        bg = "\e[48;2;#{bg_rgb[0]};#{bg_rgb[1]};#{bg_rgb[2]}m"

        chars_tall.times do
          lines << (bg + (" " * @chars_wide) + RESET)
        end
        lines.join("\n")
      end
    end
  end
end
