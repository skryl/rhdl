# Main Terminal UI class

module RHDL
  module TUI
    class SimulatorTUI
      attr_reader :simulator, :running

      def initialize(simulator = nil)
        @simulator = simulator || Debug::DebugSimulator.new
        @running = false
        @screen_width = 120
        @screen_height = 40
        @buffer = nil
        @panels = {}
        @command_buffer = ""
        @mode = :normal  # :normal, :command, :help
        @auto_run = false
        @run_speed = 10  # cycles per second

        setup_panels
        setup_callbacks
      end

      def setup_panels
        # Get terminal size
        update_terminal_size

        # Calculate panel dimensions
        left_width = @screen_width * 2 / 5
        right_width = @screen_width - left_width

        top_height = @screen_height * 2 / 3
        bottom_height = @screen_height - top_height - 2

        @panels[:signals] = SignalPanel.new(
          x: 0, y: 0,
          width: left_width, height: top_height,
          title: "Signals"
        )

        @panels[:waveform] = WaveformPanel.new(
          x: left_width, y: 0,
          width: right_width, height: top_height,
          title: "Waveform"
        )

        @panels[:status] = StatusPanel.new(
          x: 0, y: top_height,
          width: @screen_width * 2 / 3, height: bottom_height,
          title: "Console"
        )

        @panels[:breakpoints] = BreakpointPanel.new(
          x: @screen_width * 2 / 3, y: top_height,
          width: @screen_width / 3, height: bottom_height,
          title: "Breakpoints"
        )
      end

      def setup_callbacks
        @simulator.on_break = -> (sim, bp) do
          @auto_run = false
          msg = bp.is_a?(Debug::Watchpoint) ? bp.description : "Breakpoint ##{bp.id}"
          log("Break: #{msg}", level: :warning)
          refresh
        end

        @simulator.on_step = -> (sim) do
          refresh
        end
      end

      def update_terminal_size
        if STDOUT.respond_to?(:winsize)
          rows, cols = STDOUT.winsize
          @screen_height = [rows - 2, 20].max
          @screen_width = [cols, 80].max
        end
      end

      # Add a component's signals to the display
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
          @panels[:signals].add_signal(full_name, wire)
          @simulator.probe(wire)
        end

        # Add probes to waveform panel
        @simulator.waveform.probes.each_value do |probe|
          @panels[:waveform].add_probe(probe) unless @panels[:waveform].probes.include?(probe)
        end
      end

      # Log a message to the status panel
      def log(message, level: :info)
        @panels[:status].add_status(message, level: level)
      end

      # Main run loop
      def run
        @running = true
        @buffer = ScreenBuffer.new(@screen_width, @screen_height)

        # Enter raw mode
        STDIN.raw do
          print ANSI.hide_cursor
          print ANSI.clear_screen

          log("RHDL Simulator TUI started", level: :success)
          log("Press 'h' for help, 'q' to quit", level: :info)

          while @running
            handle_input
            update_simulation if @auto_run
            refresh
            sleep(0.05)  # ~20 FPS
          end

          print ANSI.show_cursor
          print ANSI.clear_screen
        end
      end

      # Refresh the display
      def refresh
        @buffer.clear

        # Update breakpoint panel
        @panels[:breakpoints].breakpoints = @simulator.breakpoints

        # Render all panels
        @panels.each_value { |panel| panel.render(@buffer) }

        # Render status bar
        render_status_bar

        # Render command line if in command mode
        render_command_line if @mode == :command

        @buffer.render
      end

      private

      def render_status_bar
        y = @screen_height - 1

        # Left side - simulation status
        status = @auto_run ? "#{ANSI::GREEN}▶ RUNNING#{ANSI::RESET}" : "#{ANSI::YELLOW}⏸ PAUSED#{ANSI::RESET}"
        time_info = "T:#{@simulator.time} C:#{@simulator.current_cycle}"
        left = " #{status} │ #{time_info}"

        # Right side - help hint
        right = "h:Help q:Quit Space:Step r:Run s:Stop "

        # Center - mode indicator
        mode_str = case @mode
        when :command then "#{ANSI::CYAN}[COMMAND]#{ANSI::RESET}"
        when :help then "#{ANSI::MAGENTA}[HELP]#{ANSI::RESET}"
        else ""
        end

        padding = @screen_width - left.gsub(/\e\[[0-9;]*m/, '').length - right.length - mode_str.gsub(/\e\[[0-9;]*m/, '').length
        bar = "#{ANSI::REVERSE}#{left}#{' ' * [padding, 0].max}#{mode_str}#{right}#{ANSI::RESET}"

        @buffer.write(0, y, bar)
      end

      def render_command_line
        y = @screen_height - 2
        prompt = "#{ANSI::CYAN}:#{ANSI::RESET}#{@command_buffer}#{ANSI::BLINK}_#{ANSI::RESET}"
        @buffer.write(0, y, prompt)
      end

      def handle_input
        return unless IO.select([STDIN], nil, nil, 0.01)

        char = STDIN.read_nonblock(1) rescue nil
        return unless char

        case @mode
        when :normal
          handle_normal_mode(char)
        when :command
          handle_command_mode(char)
        when :help
          @mode = :normal  # Any key exits help
        end
      end

      def handle_normal_mode(char)
        case char
        when 'q', "\u0003"  # q or Ctrl+C
          @running = false
        when 'h', '?'
          show_help
        when ':'
          @mode = :command
          @command_buffer = ""
        when ' '  # Space - single step
          step_cycle
        when 'r'  # Run
          @auto_run = true
          log("Running simulation...", level: :success)
        when 's'  # Stop
          @auto_run = false
          log("Simulation paused", level: :warning)
        when 'n'  # Next half cycle
          step_half_cycle
        when 'c'  # Continue until breakpoint
          run_until_break
        when 'R'  # Reset
          reset_simulation
        when 'w'  # Add watch (opens command mode with 'watch ' prefilled)
          @mode = :command
          @command_buffer = "watch "
        when 'b'  # Add breakpoint
          @mode = :command
          @command_buffer = "break "
        when 'j', "\e[B"  # Down arrow
          @panels[:signals].scroll_down
        when 'k', "\e[A"  # Up arrow
          @panels[:signals].scroll_up
        when "\e"  # Escape sequence
          handle_escape_sequence
        end
      end

      def handle_escape_sequence
        # Read additional escape sequence characters
        seq = ""
        while IO.select([STDIN], nil, nil, 0.01)
          seq += STDIN.read_nonblock(1) rescue ""
        end

        case seq
        when "[A" then @panels[:signals].scroll_up
        when "[B" then @panels[:signals].scroll_down
        when "[C" then nil  # Right arrow
        when "[D" then nil  # Left arrow
        end
      end

      def handle_command_mode(char)
        case char
        when "\r", "\n"  # Enter
          execute_command(@command_buffer)
          @mode = :normal
          @command_buffer = ""
        when "\u007F", "\b"  # Backspace
          @command_buffer = @command_buffer[0..-2]
        when "\e"  # Escape
          @mode = :normal
          @command_buffer = ""
        else
          @command_buffer += char if char =~ /[[:print:]]/
        end
      end

      def execute_command(cmd)
        parts = cmd.strip.split(/\s+/)
        return if parts.empty?

        command = parts[0].downcase
        args = parts[1..-1]

        case command
        when "run", "r"
          cycles = args[0]&.to_i || 100
          run_cycles(cycles)
        when "step", "s"
          step_cycle
        when "watch", "w"
          add_watch_command(args)
        when "break", "b"
          add_break_command(args)
        when "delete", "del", "d"
          delete_breakpoint(args[0]&.to_i)
        when "clear"
          clear_command(args[0])
        when "set"
          set_signal_command(args)
        when "print", "p"
          print_signal(args[0])
        when "list", "l"
          list_signals
        when "export"
          export_vcd(args[0] || "waveform.vcd")
        when "help", "h"
          show_help
        when "quit", "q"
          @running = false
        else
          log("Unknown command: #{command}", level: :error)
        end
      end

      def add_watch_command(args)
        return log("Usage: watch <signal> [type]", level: :error) if args.empty?

        signal_path = args[0]
        watch_type = (args[1] || "change").to_sym

        # Find the wire
        wire = find_wire(signal_path)
        return log("Signal not found: #{signal_path}", level: :error) unless wire

        wp = @simulator.watch(wire, type: watch_type)
        log("Added watchpoint ##{wp.id}: #{wp.description}", level: :success)
      end

      def add_break_command(args)
        # Simple breakpoint on cycle count
        if args.empty?
          bp = @simulator.add_breakpoint { true }
          log("Added breakpoint ##{bp.id} (unconditional)", level: :success)
        elsif args[0] =~ /^\d+$/
          cycle = args[0].to_i
          bp = @simulator.add_breakpoint { |sim| sim.current_cycle >= cycle }
          log("Added breakpoint ##{bp.id} at cycle #{cycle}", level: :success)
        else
          log("Usage: break [cycle]", level: :error)
        end
      end

      def delete_breakpoint(id)
        return log("Usage: delete <breakpoint_id>", level: :error) unless id
        @simulator.remove_breakpoint(id)
        log("Deleted breakpoint ##{id}", level: :success)
      end

      def clear_command(what)
        case what
        when "breaks", "breakpoints"
          @simulator.clear_breakpoints
          log("Cleared all breakpoints", level: :success)
        when "waves", "waveform"
          @simulator.waveform.clear_all
          log("Cleared waveform data", level: :success)
        when "log", "console"
          @panels[:status].clear
        else
          log("Usage: clear [breaks|waves|log]", level: :error)
        end
      end

      def set_signal_command(args)
        return log("Usage: set <signal> <value>", level: :error) if args.size < 2

        signal_path = args[0]
        value = parse_value(args[1])

        wire = find_wire(signal_path)
        return log("Signal not found: #{signal_path}", level: :error) unless wire

        wire.set(value)
        @simulator.propagate_all
        log("Set #{signal_path} = #{value}", level: :success)
      end

      def print_signal(signal_path)
        return log("Usage: print <signal>", level: :error) unless signal_path

        wire = find_wire(signal_path)
        return log("Signal not found: #{signal_path}", level: :error) unless wire

        val = wire.get
        log("#{signal_path} = #{val} (0x#{val.to_s(16)}, 0b#{val.to_s(2)})", level: :info)
      end

      def list_signals
        @simulator.components.each do |comp|
          log("#{comp.name}:", level: :info)
          comp.inputs.each { |n, w| log("  in  #{n}: #{w.get}", level: :debug) }
          comp.outputs.each { |n, w| log("  out #{n}: #{w.get}", level: :debug) }
        end
      end

      def export_vcd(filename)
        begin
          vcd = @simulator.waveform.to_vcd
          File.write(filename, vcd)
          log("Exported waveform to #{filename}", level: :success)
        rescue => e
          log("Export failed: #{e.message}", level: :error)
        end
      end

      def find_wire(path)
        parts = path.to_s.split('.')
        return nil if parts.size < 2

        comp_name = parts[0..-2].join('.')
        signal_name = parts.last.to_sym

        comp = @simulator.components.find { |c| c.name == comp_name || c.name.end_with?(comp_name) }
        return nil unless comp

        comp.inputs[signal_name] || comp.outputs[signal_name] || comp.internal_signals[signal_name]
      end

      def parse_value(str)
        case str
        when /^0x/i then str.to_i(16)
        when /^0b/i then str.to_i(2)
        when /^0o/i then str.to_i(8)
        else str.to_i
        end
      end

      def step_cycle
        @simulator.step_cycle
        log("Stepped to cycle #{@simulator.current_cycle}", level: :debug)
      end

      def step_half_cycle
        @simulator.step_half_cycle
        log("Half cycle step", level: :debug)
      end

      def run_cycles(n)
        log("Running #{n} cycles...", level: :info)
        @simulator.run(n)
        log("Completed #{n} cycles", level: :success)
      end

      def run_until_break
        @auto_run = true
        log("Running until breakpoint...", level: :info)
      end

      def reset_simulation
        @simulator.reset
        @simulator.waveform.clear_all
        log("Simulation reset", level: :warning)
      end

      def update_simulation
        # Run one cycle per update when auto-running
        return unless @auto_run
        @simulator.step_cycle
        @auto_run = false if @simulator.paused?
      end

      def show_help
        @panels[:status].clear
        log("═══ RHDL Simulator Help ═══", level: :info)
        log("", level: :info)
        log("Keys:", level: :info)
        log("  Space  - Step one cycle", level: :debug)
        log("  n      - Step half cycle", level: :debug)
        log("  r      - Run simulation", level: :debug)
        log("  s      - Stop simulation", level: :debug)
        log("  R      - Reset simulation", level: :debug)
        log("  c      - Continue until breakpoint", level: :debug)
        log("  w      - Add watchpoint", level: :debug)
        log("  b      - Add breakpoint", level: :debug)
        log("  j/k    - Scroll signals", level: :debug)
        log("  :      - Enter command mode", level: :debug)
        log("  h/?    - Show this help", level: :debug)
        log("  q      - Quit", level: :debug)
        log("", level: :info)
        log("Commands:", level: :info)
        log("  run [n]           - Run n cycles", level: :debug)
        log("  step              - Single step", level: :debug)
        log("  watch <sig> [type]- Add watchpoint", level: :debug)
        log("  break [cycle]     - Add breakpoint", level: :debug)
        log("  delete <id>       - Delete breakpoint", level: :debug)
        log("  set <sig> <val>   - Set signal value", level: :debug)
        log("  print <sig>       - Print signal value", level: :debug)
        log("  list              - List all signals", level: :debug)
        log("  export <file>     - Export VCD", level: :debug)
        log("  clear [what]      - Clear breaks/waves/log", level: :debug)
        log("", level: :info)
        log("Watch types: change, equals, rising_edge, falling_edge", level: :debug)
        @mode = :help
      end
    end
  end
end
