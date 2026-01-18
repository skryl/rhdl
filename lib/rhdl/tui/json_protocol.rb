# JSON Protocol for Ink TUI communication

require 'json'

module RHDL
  module HDL
    module JsonProtocol
      # Convert a Wire to a signal hash
      def self.signal_to_hash(name, wire)
        value = wire.get rescue 0
        {
          name: name.to_s,
          value: value,
          width: wire.width,
          hex: "0x#{value.to_s(16).upcase.rjust((wire.width + 3) / 4, '0')}",
          binary: "0b#{value.to_s(2).rjust(wire.width, '0')}"
        }
      end

      # Convert a WaveformCapture probe to a waveform hash
      def self.probe_to_hash(probe)
        {
          name: probe.name,
          width: probe.width,
          samples: probe.samples.map { |s| { time: s[:time], value: s[:value] } }
        }
      end

      # Convert a Breakpoint to a hash
      def self.breakpoint_to_hash(bp)
        {
          id: bp.id,
          enabled: bp.enabled,
          description: bp.respond_to?(:description) ? bp.description : "Breakpoint ##{bp.id}",
          hit_count: bp.hit_count
        }
      end

      # Convert a Watchpoint to a hash
      def self.watchpoint_to_hash(wp)
        {
          id: wp.id,
          enabled: wp.enabled,
          signal: wp.wire.name.to_s,
          type: wp.type.to_s,
          value: wp.value,
          description: wp.description
        }
      end

      # Build the full simulator state hash
      def self.build_state(adapter)
        sim = adapter.simulator
        signals = adapter.tracked_signals.map do |name, wire|
          signal_to_hash(name, wire)
        end

        waveforms = if sim.respond_to?(:waveform) && sim.waveform
          sim.waveform.probes.values.map { |p| probe_to_hash(p) }
        else
          []
        end

        breakpoints = []
        watchpoints = []
        if sim.respond_to?(:breakpoints)
          sim.breakpoints.each do |bp|
            if bp.is_a?(Watchpoint)
              watchpoints << watchpoint_to_hash(bp)
            else
              breakpoints << breakpoint_to_hash(bp)
            end
          end
        end

        {
          time: sim.respond_to?(:time) ? sim.time : 0,
          cycle: sim.respond_to?(:current_cycle) ? sim.current_cycle : 0,
          running: adapter.running?,
          paused: sim.respond_to?(:paused?) ? sim.paused? : false,
          signals: signals,
          waveforms: waveforms,
          breakpoints: breakpoints,
          watchpoints: watchpoints
        }
      end

      # Send an event to the TUI
      def self.send_event(io, event)
        io.puts(JSON.generate(event))
        io.flush
      rescue Errno::EPIPE, IOError
        # TUI process died
      end

      # Parse a command from the TUI
      def self.parse_command(line)
        JSON.parse(line, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
