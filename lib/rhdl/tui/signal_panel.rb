# Signal viewer panel

module RHDL
  module TUI
    class SignalPanel < Panel
      attr_accessor :signals

      def initialize(**opts)
        super(**opts)
        @signals = []  # Array of {name:, wire:, format:}
        @scroll_offset = 0
      end

      def add_signal(name, wire, format: :auto)
        @signals << { name: name, wire: wire, format: format }
      end

      def remove_signal(name)
        @signals.reject! { |s| s[:name] == name }
      end

      def clear_signals
        @signals.clear
      end

      def scroll_up
        @scroll_offset = [@scroll_offset - 1, 0].max
      end

      def scroll_down
        max_scroll = [@signals.size - (@height - 3), 0].max
        @scroll_offset = [@scroll_offset + 1, max_scroll].min
      end

      def render_content(buffer)
        content_width = @width - 4
        max_lines = @height - 3

        visible_signals = @signals[@scroll_offset, max_lines] || []

        visible_signals.each_with_index do |sig, i|
          y_pos = @y + 1 + i
          name = sig[:name].to_s.ljust(20)[0, 20]
          value = format_signal_value(sig[:wire], sig[:format])

          # Highlight changed values
          color = sig[:changed] ? ANSI::BRIGHT_YELLOW : ANSI::WHITE
          line = "#{color}#{name} #{ANSI::BRIGHT_GREEN}#{value}#{ANSI::RESET}"

          buffer.write(@x + 2, y_pos, line[0, content_width])
        end

        # Scroll indicator
        if @signals.size > max_lines
          indicator = "[#{@scroll_offset + 1}-#{[@scroll_offset + max_lines, @signals.size].min}/#{@signals.size}]"
          buffer.write(@x + @width - indicator.length - 2, @y + @height - 1, indicator)
        end
      end

      private

      def format_signal_value(wire, format)
        val = wire.get
        width = wire.width

        case format
        when :binary
          "0b#{val.to_s(2).rjust(width, '0')}"
        when :hex
          "0x#{val.to_s(16).rjust((width / 4.0).ceil, '0').upcase}"
        when :decimal
          val.to_s
        when :signed
          # Interpret as signed
          if val >= (1 << (width - 1))
            (val - (1 << width)).to_s
          else
            val.to_s
          end
        else # :auto
          if width == 1
            val == 1 ? "HIGH" : "LOW"
          elsif width <= 4
            "#{val} (0b#{val.to_s(2).rjust(width, '0')})"
          elsif width <= 8
            "0x#{val.to_s(16).rjust(2, '0').upcase} (#{val})"
          else
            "0x#{val.to_s(16).rjust((width / 4.0).ceil, '0').upcase}"
          end
        end
      end
    end
  end
end
