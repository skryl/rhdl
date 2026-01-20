# HDL Signal Probing - WaveformCapture
# Manages multiple signal probes for a simulation

module RHDL
  module Debug
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
  end
end
