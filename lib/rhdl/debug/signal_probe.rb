# HDL Signal Probing - SignalProbe
# Records signal transitions over time for waveform viewing

module RHDL
  module Debug
    # Records signal transitions over time for waveform viewing
    class SignalProbe
      attr_reader :name, :wire, :history, :width

      def initialize(wire, name: nil)
        @wire = wire
        @name = name || wire.name
        @width = wire.width
        @history = []  # Array of [time, value] pairs
        @enabled = true
        @last_value = nil

        # Attach to wire
        wire.on_change { |val| record_change(val) }
      end

      def record_change(value)
        return unless @enabled
        @history << [Time.now.to_f, value.to_i]
        @last_value = value.to_i
      end

      def record_at(time, value = nil)
        return unless @enabled
        val = value || @wire.get
        @history << [time, val]
        @last_value = val
      end

      def current_value
        @wire.get
      end

      def enable!
        @enabled = true
      end

      def disable!
        @enabled = false
      end

      def clear!
        @history.clear
        @last_value = nil
      end

      def transitions
        @history.size
      end

      # Get value at specific time (returns last known value before/at time)
      def value_at(time)
        result = 0
        @history.each do |t, v|
          break if t > time
          result = v
        end
        result
      end

      # Generate simple ASCII waveform
      def to_waveform(time_range: nil, width: 60)
        return "No data" if @history.empty?

        times = @history.map(&:first)
        start_time = time_range&.first || times.first
        end_time = time_range&.last || times.last
        duration = end_time - start_time
        return "Duration too short" if duration <= 0

        scale = width.to_f / duration

        if @width == 1
          # Single-bit waveform
          render_single_bit_waveform(start_time, scale, width)
        else
          # Multi-bit waveform (show transitions with values)
          render_multi_bit_waveform(start_time, scale, width)
        end
      end

      private

      def render_single_bit_waveform(start_time, scale, width)
        waveform = Array.new(width, '_')

        @history.each_cons(2) do |(t1, v1), (t2, v2)|
          pos1 = ((t1 - start_time) * scale).to_i
          pos2 = ((t2 - start_time) * scale).to_i
          next if pos1 >= width

          (pos1...[pos2, width].min).each do |i|
            waveform[i] = v1 == 1 ? '‾' : '_'
          end
        end

        # Handle last segment
        if @history.any?
          last_time, last_val = @history.last
          pos = ((last_time - start_time) * scale).to_i
          (pos...width).each { |i| waveform[i] = last_val == 1 ? '‾' : '_' }
        end

        waveform.join
      end

      def render_multi_bit_waveform(start_time, scale, width)
        result = Array.new(width, '═')
        values = []

        @history.each do |t, v|
          pos = ((t - start_time) * scale).to_i
          next if pos >= width
          result[pos] = '╳'
          values << [pos, v]
        end

        result.join + "\n" + values.map { |p, v| "#{p}:#{v.to_s(16)}" }.join(' ')
      end
    end
  end
end
