# HDL Simulator Terminal User Interface
# Interactive terminal-based GUI for simulation and debugging

require 'io/console'

module RHDL
  module HDL
    # ANSI escape code helpers
    module ANSI
      # Colors
      RESET = "\e[0m"
      BOLD = "\e[1m"
      DIM = "\e[2m"
      UNDERLINE = "\e[4m"
      BLINK = "\e[5m"
      REVERSE = "\e[7m"

      # Foreground colors
      BLACK = "\e[30m"
      RED = "\e[31m"
      GREEN = "\e[32m"
      YELLOW = "\e[33m"
      BLUE = "\e[34m"
      MAGENTA = "\e[35m"
      CYAN = "\e[36m"
      WHITE = "\e[37m"

      # Bright foreground colors
      BRIGHT_BLACK = "\e[90m"
      BRIGHT_RED = "\e[91m"
      BRIGHT_GREEN = "\e[92m"
      BRIGHT_YELLOW = "\e[93m"
      BRIGHT_BLUE = "\e[94m"
      BRIGHT_MAGENTA = "\e[95m"
      BRIGHT_CYAN = "\e[96m"
      BRIGHT_WHITE = "\e[97m"

      # Background colors
      BG_BLACK = "\e[40m"
      BG_RED = "\e[41m"
      BG_GREEN = "\e[42m"
      BG_YELLOW = "\e[43m"
      BG_BLUE = "\e[44m"
      BG_MAGENTA = "\e[45m"
      BG_CYAN = "\e[46m"
      BG_WHITE = "\e[47m"

      # Cursor control
      def self.move(row, col)
        "\e[#{row};#{col}H"
      end

      def self.clear_screen
        "\e[2J"
      end

      def self.clear_line
        "\e[2K"
      end

      def self.hide_cursor
        "\e[?25l"
      end

      def self.show_cursor
        "\e[?25h"
      end

      def self.save_cursor
        "\e[s"
      end

      def self.restore_cursor
        "\e[u"
      end
    end

    # Box drawing characters
    module BoxDraw
      HORIZONTAL = '─'
      VERTICAL = '│'
      TOP_LEFT = '┌'
      TOP_RIGHT = '┐'
      BOTTOM_LEFT = '└'
      BOTTOM_RIGHT = '┘'
      T_DOWN = '┬'
      T_UP = '┴'
      T_RIGHT = '├'
      T_LEFT = '┤'
      CROSS = '┼'
      DOUBLE_HORIZONTAL = '═'
      DOUBLE_VERTICAL = '║'
    end

    # Terminal UI Panel base class
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

    # Signal viewer panel
    class SignalPanel < Panel
      attr_accessor :signals

      def initialize(**opts)
        super(**opts)
        @signals = []  # Array of {name:, wire:, format:}
        @scroll_offset = 0
      end

      def add_signal(name, wire, format: :auto)
        @signals << { name: name, wire: wire, format: format }
      end

      def remove_signal(name)
        @signals.reject! { |s| s[:name] == name }
      end

      def clear_signals
        @signals.clear
      end

      def scroll_up
        @scroll_offset = [@scroll_offset - 1, 0].max
      end

      def scroll_down
        max_scroll = [@signals.size - (@height - 3), 0].max
        @scroll_offset = [@scroll_offset + 1, max_scroll].min
      end

      def render_content(buffer)
        content_width = @width - 4
        max_lines = @height - 3

        visible_signals = @signals[@scroll_offset, max_lines] || []

        visible_signals.each_with_index do |sig, i|
          y_pos = @y + 1 + i
          name = sig[:name].to_s.ljust(20)[0, 20]
          value = format_signal_value(sig[:wire], sig[:format])

          # Highlight changed values
          color = sig[:changed] ? ANSI::BRIGHT_YELLOW : ANSI::WHITE
          line = "#{color}#{name} #{ANSI::BRIGHT_GREEN}#{value}#{ANSI::RESET}"

          buffer.write(@x + 2, y_pos, line[0, content_width])
        end

        # Scroll indicator
        if @signals.size > max_lines
          indicator = "[#{@scroll_offset + 1}-#{[@scroll_offset + max_lines, @signals.size].min}/#{@signals.size}]"
          buffer.write(@x + @width - indicator.length - 2, @y + @height - 1, indicator)
        end
      end

      private

      def format_signal_value(wire, format)
        val = wire.get
        width = wire.width

        case format
        when :binary
          "0b#{val.to_s(2).rjust(width, '0')}"
        when :hex
          "0x#{val.to_s(16).rjust((width / 4.0).ceil, '0').upcase}"
        when :decimal
          val.to_s
        when :signed
          # Interpret as signed
          if val >= (1 << (width - 1))
            (val - (1 << width)).to_s
          else
            val.to_s
          end
        else # :auto
          if width == 1
            val == 1 ? "HIGH" : "LOW"
          elsif width <= 4
            "#{val} (0b#{val.to_s(2).rjust(width, '0')})"
          elsif width <= 8
            "0x#{val.to_s(16).rjust(2, '0').upcase} (#{val})"
          else
            "0x#{val.to_s(16).rjust((width / 4.0).ceil, '0').upcase}"
          end
        end
      end
    end

    # Waveform display panel
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

    # Command/status panel
    class StatusPanel < Panel
      attr_accessor :status_lines, :command_history

      def initialize(**opts)
        super(**opts)
        @status_lines = []
        @command_history = []
        @max_history = 100
      end

      def add_status(message, level: :info)
        color = case level
        when :error then ANSI::RED
        when :warning then ANSI::YELLOW
        when :success then ANSI::GREEN
        when :debug then ANSI::BRIGHT_BLACK
        else ANSI::WHITE
        end

        timestamp = Time.now.strftime("%H:%M:%S")
        @status_lines << { time: timestamp, message: message, color: color }
        @status_lines.shift while @status_lines.size > @max_history
      end

      def clear
        @status_lines.clear
      end

      def render_content(buffer)
        content_width = @width - 4
        max_lines = @height - 3

        visible_lines = @status_lines.last(max_lines)

        visible_lines.each_with_index do |line, i|
          y_pos = @y + 1 + i
          text = "#{ANSI::DIM}#{line[:time]}#{ANSI::RESET} #{line[:color]}#{line[:message]}#{ANSI::RESET}"
          # Truncate if needed
          buffer.write(@x + 2, y_pos, text[0, content_width + 30])  # Extra for escape codes
        end
      end
    end

    # Breakpoint list panel
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
          desc = bp.is_a?(Watchpoint) ? bp.description : "custom"
          hits = "hits:#{bp.hit_count}"

          line = "#{status} ##{bp.id} #{desc} (#{hits})"
          if selected
            line = "#{ANSI::REVERSE}#{line}#{ANSI::RESET}"
          end

          buffer.write(@x + 2, y_pos, line[0, content_width + 20])
        end
      end
    end

    # Screen buffer for efficient rendering
    class ScreenBuffer
      def initialize(width, height)
        @width = width
        @height = height
        @buffer = Array.new(height) { ' ' * width }
        @dirty = true
      end

      def write(x, y, text)
        return if y < 0 || y >= @height || x >= @width
        return if x < 0

        # Strip ANSI codes for length calculation but preserve them in output
        visible_text = text.gsub(/\e\[[0-9;]*m/, '')
        max_len = @width - x

        if visible_text.length > max_len
          # Need to truncate while preserving ANSI codes
          text = truncate_with_ansi(text, max_len)
        end

        # Insert into buffer line
        line = @buffer[y]
        @buffer[y] = line[0, x].to_s.ljust(x) + text + (line[x + visible_text.length..-1] || '')
        @dirty = true
      end

      def clear
        @buffer = Array.new(@height) { ' ' * @width }
        @dirty = true
      end

      def render
        return unless @dirty
        output = ANSI.clear_screen + ANSI.move(1, 1)
        output += @buffer.join("\n")
        print output
        @dirty = false
      end

      private

      def truncate_with_ansi(text, max_visible_len)
        visible_count = 0
        result = ""
        in_escape = false

        text.each_char do |ch|
          if ch == "\e"
            in_escape = true
            result += ch
          elsif in_escape
            result += ch
            in_escape = false if ch =~ /[a-zA-Z]/
          else
            break if visible_count >= max_visible_len
            result += ch
            visible_count += 1
          end
        end

        result + ANSI::RESET
      end
    end

    # Main Terminal UI class
    class SimulatorTUI
      attr_reader :simulator, :running

      def initialize(simulator = nil)
        @simulator = simulator || DebugSimulator.new
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
          msg = bp.is_a?(Watchpoint) ? bp.description : "Breakpoint ##{bp.id}"
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
