# Screen buffer for efficient rendering

module RHDL
  module HDL
    class ScreenBuffer
      def initialize(width, height)
        @width = width
        @height = height
        @buffer = Array.new(height) { ' ' * width }
        @dirty = true
      end

      def write(x, y, text)
        return if y < 0 || y >= @height || x >= @width
        return if x < 0

        # Strip ANSI codes for length calculation but preserve them in output
        visible_text = text.gsub(/\e\[[0-9;]*m/, '')
        max_len = @width - x

        if visible_text.length > max_len
          # Need to truncate while preserving ANSI codes
          text = truncate_with_ansi(text, max_len)
        end

        # Insert into buffer line
        line = @buffer[y]
        @buffer[y] = line[0, x].to_s.ljust(x) + text + (line[x + visible_text.length..-1] || '')
        @dirty = true
      end

      def clear
        @buffer = Array.new(@height) { ' ' * @width }
        @dirty = true
      end

      def render
        return unless @dirty
        output = ANSI.clear_screen + ANSI.move(1, 1)
        output += @buffer.join("\n")
        print output
        @dirty = false
      end

      private

      def truncate_with_ansi(text, max_visible_len)
        visible_count = 0
        result = ""
        in_escape = false

        text.each_char do |ch|
          if ch == "\e"
            in_escape = true
            result += ch
          elsif in_escape
            result += ch
            in_escape = false if ch =~ /[a-zA-Z]/
          else
            break if visible_count >= max_visible_len
            result += ch
            visible_count += 1
          end
        end

        result + ANSI::RESET
      end
    end
  end
end
