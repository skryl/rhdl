# Waveform display panel

module RHDL
  module HDL
    class WaveformPanel < Panel
      attr_accessor :probes

      def initialize(**opts)
        super(**opts)
        @probes = []
        @time_window = 50  # How many time units to show
        @scroll_time = 0
      end

      def add_probe(probe)
        @probes << probe
      end

      def set_time_window(window)
        @time_window = window
      end

      def render_content(buffer)
        content_width = @width - 4
        max_lines = @height - 3
        name_width = 12
        wave_width = content_width - name_width - 3

        @probes.take(max_lines).each_with_index do |probe, i|
          y_pos = @y + 1 + i
          name = probe.name.to_s[0, name_width].ljust(name_width)
          waveform = render_mini_waveform(probe, wave_width)

          buffer.write(@x + 2, y_pos, "#{ANSI::CYAN}#{name}#{ANSI::RESET}│#{waveform}")
        end

        # Time axis
        if @probes.any?
          time_axis = render_time_axis(wave_width)
          buffer.write(@x + 2 + name_width + 1, @y + @height - 2, time_axis)
        end
      end

      private

      def render_mini_waveform(probe, width)
        return ' ' * width if probe.history.empty?

        history = probe.history
        min_time = history.first[0]
        max_time = history.last[0]
        duration = max_time - min_time
        return ' ' * width if duration <= 0

        result = Array.new(width, ' ')

        if probe.width == 1
          # Single-bit waveform
          history.each_cons(2) do |(t1, v1), (t2, v2)|
            start_pos = ((t1 - min_time) / duration * width).to_i
            end_pos = ((t2 - min_time) / duration * width).to_i
            (start_pos...[end_pos, width].min).each do |pos|
              result[pos] = v1 == 1 ? '▀' : '▄'
            end
          end
          # Last segment
          last_time, last_val = history.last
          start_pos = ((last_time - min_time) / duration * width).to_i
          (start_pos...width).each { |pos| result[pos] = last_val == 1 ? '▀' : '▄' }
        else
          # Multi-bit - show transitions
          prev_pos = -1
          history.each do |t, v|
            pos = ((t - min_time) / duration * width).to_i
            next if pos == prev_pos || pos >= width
            result[pos] = '┃'
            prev_pos = pos
          end
        end

        # Colorize
        result.map do |ch|
          case ch
          when '▀' then "#{ANSI::GREEN}#{ch}#{ANSI::RESET}"
          when '▄' then "#{ANSI::BRIGHT_BLACK}#{ch}#{ANSI::RESET}"
          when '┃' then "#{ANSI::YELLOW}#{ch}#{ANSI::RESET}"
          else ch
          end
        end.join
      end

      def render_time_axis(width)
        axis = '└' + '─' * (width - 2) + '┘'
        axis
      end
    end
  end
end
