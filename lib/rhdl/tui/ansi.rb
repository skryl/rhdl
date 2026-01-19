# ANSI escape code helpers

module RHDL
  module HDL
    module ANSI
      # Colors
      RESET = "\e[0m"
      BOLD = "\e[1m"
      DIM = "\e[2m"
      UNDERLINE = "\e[4m"
      BLINK = "\e[5m"
      REVERSE = "\e[7m"

      # Foreground colors
      BLACK = "\e[30m"
      RED = "\e[31m"
      GREEN = "\e[32m"
      YELLOW = "\e[33m"
      BLUE = "\e[34m"
      MAGENTA = "\e[35m"
      CYAN = "\e[36m"
      WHITE = "\e[37m"

      # Bright foreground colors
      BRIGHT_BLACK = "\e[90m"
      BRIGHT_RED = "\e[91m"
      BRIGHT_GREEN = "\e[92m"
      BRIGHT_YELLOW = "\e[93m"
      BRIGHT_BLUE = "\e[94m"
      BRIGHT_MAGENTA = "\e[95m"
      BRIGHT_CYAN = "\e[96m"
      BRIGHT_WHITE = "\e[97m"

      # Background colors
      BG_BLACK = "\e[40m"
      BG_RED = "\e[41m"
      BG_GREEN = "\e[42m"
      BG_YELLOW = "\e[43m"
      BG_BLUE = "\e[44m"
      BG_MAGENTA = "\e[45m"
      BG_CYAN = "\e[46m"
      BG_WHITE = "\e[47m"

      # Cursor control
      def self.move(row, col)
        "\e[#{row};#{col}H"
      end

      def self.clear_screen
        "\e[2J"
      end

      def self.clear_line
        "\e[2K"
      end

      def self.hide_cursor
        "\e[?25l"
      end

      def self.show_cursor
        "\e[?25h"
      end

      def self.save_cursor
        "\e[s"
      end

      def self.restore_cursor
        "\e[u"
      end
    end
  end
end
