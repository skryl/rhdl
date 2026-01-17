# HDL Signal Probing - DebugSimulator
# Enhanced simulator with debugging support

module RHDL
  module HDL
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
