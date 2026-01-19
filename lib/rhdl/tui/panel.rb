# Terminal UI Panel base class

module RHDL
  module HDL
    class Panel
      attr_accessor :x, :y, :width, :height, :title, :visible

      def initialize(x:, y:, width:, height:, title: nil)
        @x = x
        @y = y
        @width = width
        @height = height
        @title = title
        @visible = true
        @content_lines = []
      end

      def render(buffer)
        return unless @visible

        # Draw border
        draw_border(buffer)

        # Draw title
        if @title
          title_str = " #{@title} "
          title_x = @x + (@width - title_str.length) / 2
          buffer.write(title_x, @y, "#{ANSI::BOLD}#{ANSI::CYAN}#{title_str}#{ANSI::RESET}")
        end

        # Draw content
        render_content(buffer)
      end

      def render_content(buffer)
        # Override in subclasses
      end

      private

      def draw_border(buffer)
        # Top border
        buffer.write(@x, @y, BoxDraw::TOP_LEFT + BoxDraw::HORIZONTAL * (@width - 2) + BoxDraw::TOP_RIGHT)

        # Side borders
        (1...@height - 1).each do |i|
          buffer.write(@x, @y + i, BoxDraw::VERTICAL)
          buffer.write(@x + @width - 1, @y + i, BoxDraw::VERTICAL)
        end

        # Bottom border
        buffer.write(@x, @y + @height - 1, BoxDraw::BOTTOM_LEFT + BoxDraw::HORIZONTAL * (@width - 2) + BoxDraw::BOTTOM_RIGHT)
      end
    end
  end
end
