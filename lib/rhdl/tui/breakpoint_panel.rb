# Breakpoint list panel

module RHDL
  module TUI
    class BreakpointPanel < Panel
      attr_accessor :breakpoints

      def initialize(**opts)
        super(**opts)
        @breakpoints = []
        @selected_index = 0
      end

      def render_content(buffer)
        content_width = @width - 4
        max_lines = @height - 3

        if @breakpoints.empty?
          buffer.write(@x + 2, @y + 1, "#{ANSI::DIM}No breakpoints#{ANSI::RESET}")
          return
        end

        @breakpoints.take(max_lines).each_with_index do |bp, i|
          y_pos = @y + 1 + i
          selected = i == @selected_index

          status = bp.enabled ? "#{ANSI::GREEN}●#{ANSI::RESET}" : "#{ANSI::RED}○#{ANSI::RESET}"
          desc = bp.is_a?(Debug::Watchpoint) ? bp.description : "custom"
          hits = "hits:#{bp.hit_count}"

          line = "#{status} ##{bp.id} #{desc} (#{hits})"
          if selected
            line = "#{ANSI::REVERSE}#{line}#{ANSI::RESET}"
          end

          buffer.write(@x + 2, y_pos, line[0, content_width + 20])
        end
      end
    end
  end
end
