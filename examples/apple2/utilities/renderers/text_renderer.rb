# frozen_string_literal: true

# Apple II Text Mode Renderer
# Renders Apple II text screen (40x24 characters)

module RHDL
  module Examples
    module Apple2
      # Renders Apple II text mode screen to terminal
    class TextRenderer
      SCREEN_ROWS = 24
      SCREEN_COLS = 40

      # ANSI escape codes
      ESC = "\e"
      GREEN_FG = "#{ESC}[32m"
      BLACK_BG = "#{ESC}[40m"
      NORMAL_VIDEO = "#{ESC}[0m"

      def initialize(options = {})
        @green_screen = options[:green] || false
      end

      # Render screen array to string with borders
      # screen_array: 2D array of character codes (24 rows x 40 cols)
      def render(screen_array)
        output = String.new

        output << GREEN_FG << BLACK_BG if @green_screen

        # Border top
        output << "+" << ("-" * SCREEN_COLS) << "+\n"

        # Screen content
        screen_array.each do |line|
          output << "|"
          line.each do |char_code|
            char = (char_code & 0x7F).chr
            char = ' ' if char_code < 0x20
            output << char
          end
          output << "|\n"
        end

        # Border bottom
        output << "+" << ("-" * SCREEN_COLS) << "+"

        output << NORMAL_VIDEO if @green_screen

        output
      end

      # Render to array of lines (without newlines)
      def render_lines(screen_array)
        render(screen_array).split("\n")
      end
    end
  end
  end
end
