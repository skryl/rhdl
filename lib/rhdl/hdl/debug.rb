# HDL Signal Probing and Debugging
# Provides waveform capture, breakpoints, and debugging features

module RHDL
  module HDL
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

    # Manages multiple signal probes for a simulation
    class WaveformCapture
      attr_reader :probes, :time_step

      def initialize
        @probes = {}
        @time = 0
        @time_step = 1
        @recording = false
      end

      def add_probe(wire, name: nil)
        probe_name = name || wire.name
        probe = SignalProbe.new(wire, name: probe_name)
        @probes[probe_name] = probe
        probe
      end

      def remove_probe(name)
        @probes.delete(name)
      end

      def start_recording
        @recording = true
        @time = 0
      end

      def stop_recording
        @recording = false
      end

      def capture_snapshot
        return unless @recording
        @probes.each_value do |probe|
          probe.record_at(@time)
        end
        @time += @time_step
      end

      def clear_all
        @probes.each_value(&:clear!)
        @time = 0
      end

      # Export to VCD (Value Change Dump) format for viewing in GTKWave etc.
      def to_vcd(timescale: "1ns")
        vcd = []
        vcd << "$timescale #{timescale} $end"
        vcd << "$scope module top $end"

        # Declare variables
        @probes.each_with_index do |(name, probe), i|
          id = (33 + i).chr  # VCD identifiers start at '!'
          probe.instance_variable_set(:@vcd_id, id)
          vcd << "$var wire #{probe.width} #{id} #{name.to_s.gsub('.', '_')} $end"
        end

        vcd << "$upscope $end"
        vcd << "$enddefinitions $end"

        # Dump initial values
        vcd << "$dumpvars"
        @probes.each do |name, probe|
          id = probe.instance_variable_get(:@vcd_id)
          val = probe.history.first&.last || 0
          if probe.width == 1
            vcd << "#{val}#{id}"
          else
            vcd << "b#{val.to_s(2)} #{id}"
          end
        end
        vcd << "$end"

        # Dump changes
        all_events = []
        @probes.each do |name, probe|
          id = probe.instance_variable_get(:@vcd_id)
          probe.history.each do |time, value|
            all_events << [time, id, value, probe.width]
          end
        end

        all_events.sort_by(&:first).each do |time, id, value, width|
          vcd << "##{(time * 1000).to_i}"
          if width == 1
            vcd << "#{value}#{id}"
          else
            vcd << "b#{value.to_s(2)} #{id}"
          end
        end

        vcd.join("\n")
      end

      # Simple text-based waveform display
      def display(width: 60)
        return "No probes configured" if @probes.empty?

        max_name_len = @probes.keys.map { |n| n.to_s.length }.max
        lines = []

        @probes.each do |name, probe|
          padded_name = name.to_s.ljust(max_name_len)
          waveform = probe.to_waveform(width: width)
          lines << "#{padded_name} │ #{waveform}"
        end

        lines.join("\n")
      end
    end

    # Breakpoint for simulation debugging
    class Breakpoint
      attr_reader :id, :condition, :hit_count, :enabled

      @@next_id = 1

      def initialize(condition:, &block)
        @id = @@next_id
        @@next_id += 1
        @condition = condition
        @callback = block
        @hit_count = 0
        @enabled = true
      end

      def check(context)
        return false unless @enabled
        result = @condition.call(context)
        if result
          @hit_count += 1
          @callback&.call(context)
        end
        result
      end

      def enable!
        @enabled = true
      end

      def disable!
        @enabled = false
      end

      def reset!
        @hit_count = 0
      end
    end

    # Watchpoint - break when a signal changes or matches a value
    class Watchpoint < Breakpoint
      attr_reader :wire, :watch_type, :watch_value

      def initialize(wire, type: :change, value: nil, &block)
        @wire = wire
        @watch_type = type
        @watch_value = value
        @last_value = wire.get

        condition = case type
        when :change
          -> (_) { check_change }
        when :equals
          -> (_) { wire.get == value }
        when :not_equals
          -> (_) { wire.get != value }
        when :greater
          -> (_) { wire.get > value }
        when :less
          -> (_) { wire.get < value }
        when :rising_edge
          -> (_) { check_rising_edge }
        when :falling_edge
          -> (_) { check_falling_edge }
        else
          -> (_) { false }
        end

        super(condition: condition, &block)
      end

      def check_change
        current = @wire.get
        changed = current != @last_value
        @last_value = current
        changed
      end

      def check_rising_edge
        current = @wire.get
        rising = @last_value == 0 && current == 1
        @last_value = current
        rising
      end

      def check_falling_edge
        current = @wire.get
        falling = @last_value == 1 && current == 0
        @last_value = current
        falling
      end

      def description
        case @watch_type
        when :change then "#{@wire.name} changes"
        when :equals then "#{@wire.name} == #{@watch_value}"
        when :not_equals then "#{@wire.name} != #{@watch_value}"
        when :greater then "#{@wire.name} > #{@watch_value}"
        when :less then "#{@wire.name} < #{@watch_value}"
        when :rising_edge then "#{@wire.name} ↑"
        when :falling_edge then "#{@wire.name} ↓"
        else "unknown"
        end
      end
    end

    # Enhanced simulator with debugging support
    class DebugSimulator < Simulator
      attr_reader :breakpoints, :waveform, :step_mode, :current_cycle
      attr_accessor :on_break, :on_step

      def initialize
        super
        @breakpoints = []
        @waveform = WaveformCapture.new
        @step_mode = false
        @paused = false
        @current_cycle = 0
        @on_break = nil
        @on_step = nil
        @signal_watches = {}
      end

      # Add a probe to track a signal
      def probe(wire_or_component, signal_name = nil)
        wire = if wire_or_component.is_a?(Wire)
          wire_or_component
        elsif signal_name
          wire_or_component.outputs[signal_name] ||
          wire_or_component.inputs[signal_name] ||
          wire_or_component.internal_signals[signal_name]
        else
          raise ArgumentError, "Must provide wire or component with signal name"
        end

        raise ArgumentError, "Wire not found" unless wire
        @waveform.add_probe(wire)
      end

      # Add breakpoint
      def add_breakpoint(condition = nil, &block)
        cond = condition || block || -> (_) { true }
        bp = Breakpoint.new(condition: cond)
        @breakpoints << bp
        bp
      end

      # Add watchpoint on a signal
      def watch(wire, type: :change, value: nil, &block)
        wp = Watchpoint.new(wire, type: type, value: value, &block)
        @breakpoints << wp
        wp
      end

      # Remove breakpoint
      def remove_breakpoint(bp_or_id)
        id = bp_or_id.is_a?(Breakpoint) ? bp_or_id.id : bp_or_id
        @breakpoints.reject! { |bp| bp.id == id }
      end

      # Clear all breakpoints
      def clear_breakpoints
        @breakpoints.clear
      end

      # Enable step-by-step mode
      def enable_step_mode
        @step_mode = true
      end

      # Disable step-by-step mode
      def disable_step_mode
        @step_mode = false
      end

      # Pause simulation
      def pause
        @paused = true
      end

      # Resume simulation
      def resume
        @paused = false
      end

      # Check if simulation is paused
      def paused?
        @paused
      end

      # Run simulation with debugging support
      def run(cycles, &block)
        @waveform.start_recording

        cycles.times do |cycle|
          break if @paused

          @current_cycle = cycle

          # Clock low -> high
          @clocks.each(&:tick)
          propagate_all
          @waveform.capture_snapshot

          # Check breakpoints
          if check_breakpoints
            @on_break&.call(self, triggered_breakpoint)
            break if @paused
          end

          # Step mode callback
          if @step_mode
            @on_step&.call(self)
            break if @paused
          end

          # User callback
          block&.call(self, cycle)

          # Clock high -> low
          @clocks.each(&:tick)
          propagate_all
          @waveform.capture_snapshot

          @time += 1
        end

        @waveform.stop_recording
      end

      # Single cycle step
      def step_cycle
        @current_cycle += 1

        @clocks.each(&:tick)
        propagate_all
        @waveform.capture_snapshot if @waveform

        @clocks.each(&:tick)
        propagate_all
        @waveform.capture_snapshot if @waveform

        @time += 1
        check_breakpoints
      end

      # Half cycle step (just clock edge)
      def step_half_cycle
        @clocks.each(&:tick)
        propagate_all
        @waveform.capture_snapshot if @waveform
        check_breakpoints
      end

      # Get current state of all signals
      def signal_state
        state = {}
        @components.each do |comp|
          comp.inputs.each { |name, wire| state["#{comp.name}.#{name}"] = wire.get }
          comp.outputs.each { |name, wire| state["#{comp.name}.#{name}"] = wire.get }
        end
        state
      end

      # Get signal value by path
      def get_signal(path)
        parts = path.to_s.split('.')
        return nil if parts.size < 2

        comp_name = parts[0..-2].join('.')
        signal_name = parts.last.to_sym

        comp = @components.find { |c| c.name == comp_name }
        return nil unless comp

        wire = comp.outputs[signal_name] || comp.inputs[signal_name]
        wire&.get
      end

      # Dump current simulation state
      def dump_state
        lines = []
        lines << "=== Simulation State ==="
        lines << "Time: #{@time}  Cycle: #{@current_cycle}  Paused: #{@paused}"
        lines << ""

        @components.each do |comp|
          lines << "#{comp.name}:"
          lines << "  Inputs:"
          comp.inputs.each { |name, wire| lines << "    #{name}: #{format_value(wire)}" }
          lines << "  Outputs:"
          comp.outputs.each { |name, wire| lines << "    #{name}: #{format_value(wire)}" }
          lines << ""
        end

        lines << "Breakpoints: #{@breakpoints.size}"
        @breakpoints.each do |bp|
          status = bp.enabled ? "enabled" : "disabled"
          desc = bp.is_a?(Watchpoint) ? bp.description : "custom"
          lines << "  ##{bp.id}: #{desc} (#{status}, hits: #{bp.hit_count})"
        end

        lines.join("\n")
      end

      private

      def check_breakpoints
        @triggered_breakpoint = nil
        @breakpoints.each do |bp|
          if bp.check(self)
            @triggered_breakpoint = bp
            return true
          end
        end
        false
      end

      attr_reader :triggered_breakpoint

      def format_value(wire)
        val = wire.get
        width = wire.width
        if width <= 4
          "#{val} (0b#{val.to_s(2).rjust(width, '0')})"
        elsif width <= 8
          "0x#{val.to_s(16).rjust(2, '0')} (#{val})"
        else
          "0x#{val.to_s(16).rjust((width / 4.0).ceil, '0')}"
        end
      end
    end
  end
end
