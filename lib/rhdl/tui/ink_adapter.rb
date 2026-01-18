# Ink TUI Adapter
# Manages communication between Ruby simulator and Node.js Ink TUI

require 'open3'
require 'json'
require_relative 'json_protocol'

module RHDL
  module HDL
    class InkAdapter
      attr_reader :simulator, :tracked_signals

      def initialize(simulator = nil)
        @simulator = simulator || DebugSimulator.new
        @tracked_signals = {}
        @running = false
        @auto_run = false
        @tui_process = nil
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thread = nil

        setup_callbacks
      end

      def running?
        @running
      end

      def auto_running?
        @auto_run
      end

      # Add a component's signals to tracking
      def add_component(component, signals: :all)
        signal_list = case signals
        when :all
          component.inputs.keys + component.outputs.keys
        when :inputs
          component.inputs.keys
        when :outputs
          component.outputs.keys
        when Array
          signals
        else
          []
        end

        signal_list.each do |sig_name|
          wire = component.inputs[sig_name] || component.outputs[sig_name]
          next unless wire
          full_name = "#{component.name}.#{sig_name}"
          @tracked_signals[full_name] = wire
          @simulator.probe(wire) if @simulator.respond_to?(:probe)
        end
      end

      # Start the TUI
      def run
        @running = true
        start_ink_process

        # Main event loop
        loop do
          break unless @running
          break unless @wait_thread&.alive?

          # Check for input from TUI (non-blocking)
          handle_tui_input

          # Run simulation step if auto-running
          if @auto_run && !@simulator.paused?
            @simulator.step_cycle
            send_state
          end

          sleep(0.01) # Small sleep to prevent CPU spinning
        end

        cleanup
      end

      # Stop the TUI
      def stop
        @running = false
        send_event(type: 'quit')
      end

      private

      def setup_callbacks
        return unless @simulator.respond_to?(:on_break=)

        @simulator.on_break = ->(sim, bp) do
          @auto_run = false
          msg = bp.is_a?(Watchpoint) ? bp.description : "Breakpoint ##{bp.id}"
          send_event(type: 'break', breakpoint: JsonProtocol.breakpoint_to_hash(bp), message: "Break: #{msg}")
          send_state
        end

        @simulator.on_step = ->(sim) do
          send_state if @running
        end
      end

      def start_ink_process
        tui_dir = File.expand_path('../../../../tui-ink', __FILE__)

        # Check if TUI is built
        unless File.exist?(File.join(tui_dir, 'dist', 'index.js'))
          raise "Ink TUI not built. Run 'cd #{tui_dir} && npm install && npm run build'"
        end

        # Start the Node.js process
        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(
          'node', File.join(tui_dir, 'dist', 'index.js'),
          chdir: tui_dir
        )

        # Send ready event
        send_event(type: 'ready')
        send_log("RHDL Ink TUI started", level: :success)
        send_log("Press 'h' for help, 'q' to quit", level: :info)
        send_state
      end

      def handle_tui_input
        return unless @stdout

        # Non-blocking read
        begin
          while IO.select([@stdout], nil, nil, 0)
            line = @stdout.gets
            break unless line
            process_command(line.strip)
          end
        rescue IOError, Errno::EPIPE
          @running = false
        end
      end

      def process_command(line)
        cmd = JsonProtocol.parse_command(line)
        return unless cmd

        case cmd[:type]
        when 'init'
          send_event(type: 'ready')
          send_state

        when 'get_state'
          send_state

        when 'step'
          @simulator.step_cycle
          send_log("Stepped to cycle #{@simulator.current_cycle}", level: :debug)
          send_state

        when 'step_half'
          @simulator.step_half_cycle
          send_log("Half cycle step", level: :debug)
          send_state

        when 'run'
          cycles = cmd[:cycles]
          if cycles
            send_log("Running #{cycles} cycles...", level: :info)
            @simulator.run(cycles)
            send_log("Completed #{cycles} cycles", level: :success)
          else
            @auto_run = true
            send_log("Running simulation...", level: :success)
          end
          send_state

        when 'stop'
          @auto_run = false
          send_log("Simulation paused", level: :warning)
          send_state

        when 'reset'
          @simulator.reset
          @simulator.waveform&.clear_all
          send_log("Simulation reset", level: :warning)
          send_state

        when 'continue'
          @auto_run = true
          send_log("Running until breakpoint...", level: :info)

        when 'set_signal'
          set_signal(cmd[:path], cmd[:value])

        when 'add_breakpoint'
          add_breakpoint(cmd[:cycle])

        when 'add_watchpoint'
          add_watchpoint(cmd[:signal], cmd[:watch_type], cmd[:value])

        when 'delete_breakpoint'
          delete_breakpoint(cmd[:id])

        when 'clear_breakpoints'
          @simulator.clear_breakpoints if @simulator.respond_to?(:clear_breakpoints)
          send_log("Cleared all breakpoints", level: :success)
          send_state

        when 'clear_waveforms'
          @simulator.waveform&.clear_all
          send_log("Cleared waveform data", level: :success)
          send_state

        when 'export_vcd'
          export_vcd(cmd[:filename])

        when 'quit'
          @running = false
        end
      end

      def set_signal(path, value)
        wire = find_wire(path)
        unless wire
          send_log("Signal not found: #{path}", level: :error)
          return
        end

        wire.set(value)
        @simulator.propagate_all if @simulator.respond_to?(:propagate_all)
        send_log("Set #{path} = #{value}", level: :success)
        send_state
      end

      def add_breakpoint(cycle)
        if cycle
          bp = @simulator.add_breakpoint { |sim| sim.current_cycle >= cycle }
          send_log("Added breakpoint ##{bp.id} at cycle #{cycle}", level: :success)
        else
          bp = @simulator.add_breakpoint { true }
          send_log("Added breakpoint ##{bp.id} (unconditional)", level: :success)
        end
        send_state
      end

      def add_watchpoint(signal_path, watch_type, value)
        wire = find_wire(signal_path)
        unless wire
          send_log("Signal not found: #{signal_path}", level: :error)
          return
        end

        wp = @simulator.watch(wire, type: watch_type.to_sym, value: value)
        send_log("Added watchpoint ##{wp.id}: #{wp.description}", level: :success)
        send_state
      end

      def delete_breakpoint(id)
        @simulator.remove_breakpoint(id)
        send_log("Deleted breakpoint ##{id}", level: :success)
        send_state
      end

      def export_vcd(filename)
        vcd = @simulator.waveform&.to_vcd
        unless vcd
          send_log("No waveform data to export", level: :error)
          return
        end

        File.write(filename, vcd)
        send_log("Exported waveform to #{filename}", level: :success)
      rescue => e
        send_log("Export failed: #{e.message}", level: :error)
      end

      def find_wire(path)
        # First check tracked signals
        return @tracked_signals[path] if @tracked_signals[path]

        # Try to find in components
        parts = path.to_s.split('.')
        return nil if parts.size < 2

        comp_name = parts[0..-2].join('.')
        signal_name = parts.last.to_sym

        comp = @simulator.components.find { |c| c.name == comp_name || c.name.end_with?(comp_name) }
        return nil unless comp

        comp.inputs[signal_name] || comp.outputs[signal_name] || comp.internal_signals[signal_name]
      end

      def send_state
        state = JsonProtocol.build_state(self)
        send_event(type: 'state', state: state)
      end

      def send_log(message, level: :info)
        send_event(type: 'log', message: message, level: level.to_s)
      end

      def send_event(event)
        return unless @stdin
        JsonProtocol.send_event(@stdin, event)
      end

      def cleanup
        @stdin&.close
        @stdout&.close
        @stderr&.close
        @wait_thread&.value rescue nil
      end
    end
  end
end
