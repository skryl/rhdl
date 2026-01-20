# Command/status panel

module RHDL
  module TUI
    class StatusPanel < Panel
      attr_accessor :status_lines, :command_history

      def initialize(**opts)
        super(**opts)
        @status_lines = []
        @command_history = []
        @max_history = 100
      end

      def add_status(message, level: :info)
        color = case level
        when :error then ANSI::RED
        when :warning then ANSI::YELLOW
        when :success then ANSI::GREEN
        when :debug then ANSI::BRIGHT_BLACK
        else ANSI::WHITE
        end

        timestamp = Time.now.strftime("%H:%M:%S")
        @status_lines << { time: timestamp, message: message, color: color }
        @status_lines.shift while @status_lines.size > @max_history
      end

      def clear
        @status_lines.clear
      end

      def render_content(buffer)
        content_width = @width - 4
        max_lines = @height - 3

        visible_lines = @status_lines.last(max_lines)

        visible_lines.each_with_index do |line, i|
          y_pos = @y + 1 + i
          text = "#{ANSI::DIM}#{line[:time]}#{ANSI::RESET} #{line[:color]}#{line[:message]}#{ANSI::RESET}"
          # Truncate if needed
          buffer.write(@x + 2, y_pos, text[0, content_width + 30])  # Extra for escape codes
        end
      end
    end
  end
end
