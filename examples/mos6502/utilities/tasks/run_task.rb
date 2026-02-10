# frozen_string_literal: true

# MOS6502 Run Task
# Interactive terminal emulator for MOS6502/Apple II simulation

require 'io/console'
require_relative '../runners/headless_runner'

module RHDL
  module Examples
    module MOS6502
      module Tasks
        # Run task for MOS6502/Apple II simulation
        # Supports ISA, Ruby HDL, IR, and Verilog simulation modes
        class RunTask
      SCREEN_ROWS = 24
      SCREEN_COLS = 40

      # Hi-res display dimensions
      HIRES_WIDTH = 140   # braille chars (280 pixels / 2)
      HIRES_HEIGHT = 48   # braille chars (192 pixels / 4)

      # Display dimensions including border
      DISPLAY_WIDTH = SCREEN_COLS + 2   # 42 (40 + 2 border chars)
      DISPLAY_HEIGHT = SCREEN_ROWS + 2  # 26 (24 + 2 border lines)

      # ANSI escape codes
      ESC = "\e"
      CLEAR_SCREEN = "#{ESC}[2J"
      MOVE_HOME = "#{ESC}[H"
      HIDE_CURSOR = "#{ESC}[?25l"
      SHOW_CURSOR = "#{ESC}[?25h"
      REVERSE_VIDEO = "#{ESC}[7m"
      NORMAL_VIDEO = "#{ESC}[0m"
      GREEN_FG = "#{ESC}[32m"
      BLACK_BG = "#{ESC}[40m"
      BOLD = "#{ESC}[1m"

      attr_reader :runner, :running

        def initialize(options = {})
          @options = options
          @mode = options[:mode] || :isa
        @sim_backend = options[:sim] || default_sim_backend(@mode)

        # Create runner using HeadlessRunner factory
        @runner = HeadlessRunner.new(
          mode: @mode,
          sim: @sim_backend
        )
        @sim_type = @runner.simulator_type

        @running = false
        @last_screen = nil
        # IR/Netlist mode may be slower than ISA, adjust default speed accordingly
        default_speed = calculate_default_speed
        @cycles_per_frame = options[:speed] || default_speed
        @debug = options[:debug] || false
        @green_screen = options[:green] || false
        @hires_mode = options[:hires] || false
        @color_mode = options[:color] || false
        @composite = options[:composite] || false
        @preferred_hires_width = options[:hires_width]
        @hires_width = @preferred_hires_width || (@color_mode ? 280 : 80)
        @audio_enabled = options[:audio] != false

        # Terminal size and padding for centering
        @term_rows = 24
        @term_cols = 80
        @pad_top = 0
        @pad_left = 0
        @hires_pad_top = 0
        @hires_pad_left = 0
        update_terminal_size

        # Performance monitoring
        @start_time = nil
        @start_cycles = 0
        @last_cycles = 0
        @last_time = nil
        @current_hz = 0.0
        @frame_count = 0
        @fps = 0.0
        @last_fps_time = nil
        @fps_frame_count = 0

        # Input tracking for debug
        @last_key = nil
        @last_key_time = nil

        # Keyboard mode: :normal passes keys to emulator, :command handles runtime controls
        @keyboard_mode = :normal
      end

        def calculate_default_speed
          case @mode
        when :isa then 17_030
        when :ruby then 100
        when :ir
          case @sim_backend
          when :interpret then 100
          when :jit then 5_000
          when :compile then 10_000
          else 5_000
          end
        when :netlist then 10
        when :verilog then 17_030  # Verilator is fast like native
        else 17_030
        end
      end

      def update_terminal_size
        if $stdout.respond_to?(:winsize) && $stdout.tty?
          begin
            rows, cols = $stdout.winsize
            @term_rows = [rows, DISPLAY_HEIGHT].max
            @term_cols = [cols, DISPLAY_WIDTH].max
          rescue Errno::ENOTTY
            # Not a TTY, use defaults
          end
        end

        # Calculate padding to center the text display
        display_height = @debug ? DISPLAY_HEIGHT + 7 : DISPLAY_HEIGHT
        @pad_top = [(@term_rows - display_height) / 2, 0].max
        @pad_left = [(@term_cols - DISPLAY_WIDTH) / 2, 0].max

        # Auto-adjust hires width to fit terminal
        default_width = @color_mode ? 280 : 80
        preferred = @preferred_hires_width || default_width
        @hires_width = [preferred, @term_cols].min

        # Calculate padding for hires display
        hires_content_height = @color_mode ? 96 : HIRES_HEIGHT
        debug_panel_height = @debug ? 8 : 1
        total_content_height = hires_content_height + debug_panel_height
        hires_display_width = @hires_width

        if total_content_height <= @term_rows
          @hires_pad_top = [(@term_rows - total_content_height) / 2, 0].max
        else
          @hires_pad_top = @term_rows - total_content_height
        end
        @hires_pad_left = [(@term_cols - hires_display_width) / 2, 0].max
      end

      def load_rom(path, base_addr: 0xF800)
        puts "Loading ROM: #{path} at $#{base_addr.to_s(16).upcase}"
        bytes = File.binread(path)
        @runner.load_rom(bytes, base_addr: base_addr)
      end

      def load_program(path, base_addr: 0x0800)
        puts "Loading program: #{path} at $#{base_addr.to_s(16).upcase}"
        bytes = File.binread(path)
        @runner.load_ram(bytes, base_addr: base_addr)
      end

      def load_program_bytes(bytes, base_addr: 0x0800)
        @runner.load_ram(bytes, base_addr: base_addr)
      end

      def load_disk(path, drive: 0)
        puts "Loading disk: #{path} into drive #{drive + 1}"
        @runner.load_disk(path, drive: drive)
      end

      def setup_reset_vector(addr)
        @runner.setup_reset_vector(addr)
      end

      def run
        @running = true
        @resize_pending = false

        # Set up signal handlers
        trap('INT') do
          @running = false
          Thread.new { sleep 0.5; exit!(0) if @running == false }
        end
        trap('TERM') { @running = false; exit!(0) }
        trap('WINCH') { @resize_pending = true }

        mode_names = {
          native: "Native ISA",
          ruby: "Ruby ISA",
          hdl_ruby: "Ruby HDL",
          ir_interpret: "IR (Interpret)",
          ir_jit: "IR (JIT)",
          ir_compile: "IR (Compile)",
          hdl_verilator: "HDL (Verilator)",
          netlist_interpret: "Netlist (Interpret)",
          netlist_jit: "Netlist (JIT)",
          netlist_compile: "Netlist (Compile)"
        }
        mode = mode_names[@sim_type] || @sim_type.to_s
        audio_status = @audio_enabled ? "Audio ON" : "Audio OFF"
        puts "Starting Apple ][ emulator... [#{mode} mode, #{audio_status}]"
        if @mode == :ruby
          puts "WARNING: Ruby HDL mode is slow (for verification only)"
        elsif @mode == :ir && @sim_backend == :interpret
          puts "WARNING: IR interpret mode is slow (for verification only)"
        elsif @mode == :netlist
          puts "WARNING: Netlist mode is very slow (for verification only)"
        end
        puts "Press Ctrl+C to exit"
        puts "Press any key to continue..."
        sleep 0.5

        # Start audio if enabled
        @runner.start_audio if @audio_enabled

        # Reset the CPU
        @runner.reset

        # Initialize performance monitoring
        @start_time = Time.now
        @start_cycles = @runner.cpu_state[:cycles]
        @last_time = @start_time
        @last_cycles = @start_cycles
        @last_fps_time = @start_time
        @fps_frame_count = 0

        # Enter raw terminal mode
        begin
          IO.console.raw do
            print CLEAR_SCREEN
            print HIDE_CURSOR
            main_loop
          end
        ensure
          cleanup
        end
      end

      def stop
        @running = false
      end

      private

      def default_sim_backend(mode)
        case mode
        when :isa
          RHDL::Examples::MOS6502::NATIVE_AVAILABLE ? :native : :ruby
        when :ruby
          :ruby
        when :ir, :netlist
          :compile
        else
          nil
        end
      end

      def main_loop
        @frame_count = 0

        while @running && !@runner.halted?
          if @resize_pending
            @resize_pending = false
            update_terminal_size
            print CLEAR_SCREEN
          end

          frame_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          handle_keyboard_input

          cycles_before = @runner.cycle_count
          @runner.run_steps(@cycles_per_frame)
          cycles_after = @runner.cycle_count
          cycles_executed = cycles_after - cycles_before
          @runner.bus.tick(cycles_executed) if cycles_executed > 0

          update_performance_metrics

          if @runner.screen_dirty? || @frame_count % 10 == 0
            render_screen
            @runner.clear_screen_dirty
          end

          @frame_count += 1
          @fps_frame_count += 1

          frame_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - frame_start
          sleep_time = 0.01667 - frame_elapsed
          sleep(sleep_time) if sleep_time > 0
        end

        if @runner.halted?
          halt_row = @pad_top + DISPLAY_HEIGHT + (@debug ? 7 : 2)
          print move_cursor(halt_row, @pad_left + 1)
          puts "CPU HALTED at PC=$#{@runner.cpu_state[:pc].to_s(16).upcase.rjust(4, '0')}"
          print move_cursor(halt_row + 1, @pad_left + 1)
          puts "Press any key to exit..."
          IO.console.getch
        end
      end

      def handle_keyboard_input
        char = IO.console.read_nonblock(1)
        return unless char

        ascii = char.ord

        case ascii
        when 3 # Ctrl+C
          stop
          return
        when 27 # ESC
          handle_escape_sequence
          return
        end

        if @keyboard_mode == :command
          handle_command_key(ascii)
          return
        end

        case ascii
        when 127, 8 then ascii = 0x08
        when 10, 13 then ascii = 0x0D
        end

        ascii = ascii - 32 if ascii >= 97 && ascii <= 122

        @last_key = ascii
        @last_key_time = Time.now

        @runner.inject_key(ascii)
      rescue IO::WaitReadable, Errno::EAGAIN
        # No input available
      end

      def handle_escape_sequence
        if IO.select([IO.console], nil, nil, 0.05)
          begin
            seq = IO.console.read_nonblock(2)
            if @keyboard_mode == :command
              speed_delta = @mode == :isa ? 1000 : 100
              case seq
              when '[C' then @cycles_per_frame += speed_delta
              when '[D' then @cycles_per_frame = [@cycles_per_frame - speed_delta, speed_delta].max
              end
            else
              case seq
              when '[A' then @runner.inject_key(0x0B)
              when '[B' then @runner.inject_key(0x0A)
              when '[C' then @runner.inject_key(0x15)
              when '[D' then @runner.inject_key(0x08)
              end
            end
          rescue IO::WaitReadable, Errno::EAGAIN
            handle_esc_key
          end
        else
          handle_esc_key
        end
      end

      def handle_esc_key
        if @debug
          @keyboard_mode = @keyboard_mode == :normal ? :command : :normal
        else
          @runner.inject_key(0x1B)
        end
      end

      def handle_command_key(ascii)
        case ascii
        when 72, 104 # H or h
          @hires_mode = !@hires_mode
          print CLEAR_SCREEN
        when 67, 99 # C or c
          @color_mode = !@color_mode
          @hires_mode = true if @color_mode
          update_terminal_size
          print CLEAR_SCREEN
        when 65, 97 # A or a
          if @audio_enabled
            @runner.stop_audio
            @audio_enabled = false
          else
            @runner.start_audio
            @audio_enabled = true
          end
        end
      end

      def render_screen
        @runner.sync_video_state if @runner.respond_to?(:sync_video_state)
        @runner.sync_speaker_state if @runner.respond_to?(:sync_speaker_state)

        if @hires_mode
          render_hires_screen
        else
          render_text_screen
        end
      end

      def render_hires_screen
        output = String.new

        if @green_screen && !@color_mode
          output << GREEN_FG
          output << BLACK_BG
        end

        if @color_mode
          hires_output = @runner.bus.render_hires_color(chars_wide: @hires_width, composite: @composite)
        elsif @runner.native? && @runner.respond_to?(:cpu) && @runner.cpu.respond_to?(:render_hires_braille)
          hires_output = @runner.cpu.render_hires_braille(@hires_width, true)
        else
          hires_output = @runner.bus.render_hires_braille(chars_wide: @hires_width, invert: true)
        end
        hires_lines = hires_output.split("\n")

        hires_lines.each_with_index do |line, row|
          output << move_cursor(@hires_pad_top + row + 1, @hires_pad_left + 1)
          output << line
        end

        output << NORMAL_VIDEO if @green_screen

        if @debug
          render_debug_panel_hires(output, hires_lines)
        elsif disk_motor_on?
          status_row = @hires_pad_top + hires_lines.length + 1
          output << move_cursor(status_row, @hires_pad_left + 1)
          output << "DISK LOADING..."
        end

        print output
      end

      def render_debug_panel_hires(output, hires_lines)
        debug_width = @hires_width - 2
        debug_row = @hires_pad_top + hires_lines.length + 2

        state = @runner.cpu_state
        dc = @runner.bus.disk_controller
        sim_type = (state[:simulator_type] || 'unknown').to_s.upcase

        mode_label = @color_mode ? "[COLOR]" : "[HIRES]"
        line1 = format("PC:%04X A:%02X X:%02X Y:%02X SP:%02X P:%02X %s",
                       state[:pc], state[:a], state[:x], state[:y],
                       state[:sp], state[:p], mode_label)
        line2 = format("Sim:%-6s Cyc:%s %s %.1ffps Spd:%s",
                       sim_type, format_cycles(state[:cycles]),
                       format_hz(@current_hz), @fps,
                       format_number(@cycles_per_frame))
        kb_mode = @keyboard_mode == :command ? "CMD" : "NRM"
        line3 = format("Disk:T%02d %s | Key:%-3s | KB:%s",
                       dc.track, dc.motor_on ? "ON " : "OFF",
                       format_key(@last_key), kb_mode)
        speaker = @runner.bus.speaker
        activity = speaker.active? ? "*" : " "
        line4 = format("Audio:%s%s Tgl:%s Smp:%s",
                       speaker.status, activity,
                       format_number(speaker.toggle_count),
                       format_number(speaker.samples_written))

        line1 = line1.ljust(debug_width)[0, debug_width]
        line2 = line2.ljust(debug_width)[0, debug_width]
        line3 = line3.ljust(debug_width)[0, debug_width]
        line4 = line4.ljust(debug_width)[0, debug_width]

        output << move_cursor(debug_row, @hires_pad_left + 1)
        output << "+" << ("-" * debug_width) << "+"
        output << move_cursor(debug_row + 1, @hires_pad_left + 1)
        output << "|" << line1 << "|"
        output << move_cursor(debug_row + 2, @hires_pad_left + 1)
        output << "|" << line2 << "|"
        output << move_cursor(debug_row + 3, @hires_pad_left + 1)
        output << "|" << line3 << "|"
        output << move_cursor(debug_row + 4, @hires_pad_left + 1)
        output << "|" << line4 << "|"
        output << move_cursor(debug_row + 5, @hires_pad_left + 1)
        output << "+" << ("-" * debug_width) << "+"
      end

      def render_text_screen
        output = String.new
        output << move_cursor(@pad_top + 1, @pad_left + 1)

        if @green_screen
          output << GREEN_FG
          output << BLACK_BG
        end

        output << "+" << ("-" * SCREEN_COLS) << "+"
        output << move_cursor(@pad_top + 2, @pad_left + 1)

        screen = @runner.read_screen_array

        screen.each_with_index do |line, row|
          output << "|"
          line.each do |char_code|
            char = (char_code & 0x7F).chr
            char = ' ' if char_code < 0x20
            output << char
          end
          output << "|"
          output << move_cursor(@pad_top + 3 + row, @pad_left + 1)
        end

        output << "+" << ("-" * SCREEN_COLS) << "+"
        output << NORMAL_VIDEO if @green_screen

        if @debug
          render_debug_panel_text(output)
        end

        status_row = @pad_top + DISPLAY_HEIGHT + 1
        if disk_motor_on? && !@debug
          output << move_cursor(status_row, @pad_left + 1)
          output << "DISK LOADING..."
          output << "     "
        elsif !@debug
          output << move_cursor(status_row, @pad_left + 1)
          output << "                    "
        end

        print output
      end

      def render_debug_panel_text(output)
        debug_row = @pad_top + DISPLAY_HEIGHT + 2

        state = @runner.cpu_state
        dc = @runner.bus.disk_controller
        mode = @runner.bus.display_mode
        sim_type = (state[:simulator_type] || 'unknown').to_s.upcase

        line1 = format("PC:%04X A:%02X X:%02X Y:%02X SP:%02X P:%02X",
                       state[:pc], state[:a], state[:x], state[:y],
                       state[:sp], state[:p])
        line2 = format("Sim:%-6s Cyc:%s %s %.1ffps Spd:%s",
                       sim_type, format_cycles(state[:cycles]),
                       format_hz(@current_hz), @fps,
                       format_number(@cycles_per_frame))
        kb_mode = @keyboard_mode == :command ? "CMD" : "NRM"
        line3 = format("Disk:T%02d %s|Key:%-3s|%s|KB:%s",
                       dc.track, dc.motor_on ? "ON " : "OFF",
                       format_key(@last_key), mode.to_s.upcase, kb_mode)
        speaker = @runner.bus.speaker
        activity = speaker.active? ? "*" : " "
        line4 = format("Audio:%s%s Tgl:%s Smp:%s",
                       speaker.status, activity,
                       format_number(speaker.toggle_count),
                       format_number(speaker.samples_written))

        line1 = line1.ljust(SCREEN_COLS)[0, SCREEN_COLS]
        line2 = line2.ljust(SCREEN_COLS)[0, SCREEN_COLS]
        line3 = line3.ljust(SCREEN_COLS)[0, SCREEN_COLS]
        line4 = line4.ljust(SCREEN_COLS)[0, SCREEN_COLS]

        output << move_cursor(debug_row, @pad_left + 1)
        output << "+" << ("-" * SCREEN_COLS) << "+"
        output << move_cursor(debug_row + 1, @pad_left + 1)
        output << "|" << line1 << "|"
        output << move_cursor(debug_row + 2, @pad_left + 1)
        output << "|" << line2 << "|"
        output << move_cursor(debug_row + 3, @pad_left + 1)
        output << "|" << line3 << "|"
        output << move_cursor(debug_row + 4, @pad_left + 1)
        output << "|" << line4 << "|"
        output << move_cursor(debug_row + 5, @pad_left + 1)
        output << "+" << ("-" * SCREEN_COLS) << "+"
      end

      def format_cycles(cycles)
        if cycles >= 1_000_000
          format("%.1fM", cycles / 1_000_000.0)
        elsif cycles >= 1_000
          format("%.1fK", cycles / 1_000.0)
        else
          cycles.to_s
        end
      end

      def format_number(n)
        if n >= 1_000_000
          format("%.1fM", n / 1_000_000.0)
        elsif n >= 1_000
          format("%.1fK", n / 1_000.0)
        else
          n.to_s
        end
      end

      def update_performance_metrics
        now = Time.now
        current_cycles = @runner.cpu_state[:cycles]

        elapsed = now - @last_time
        if elapsed >= 0.5
          cycles_delta = current_cycles - @last_cycles
          @current_hz = cycles_delta / elapsed
          @last_time = now
          @last_cycles = current_cycles
        end

        fps_elapsed = now - @last_fps_time
        if fps_elapsed >= 1.0
          @fps = @fps_frame_count / fps_elapsed
          @last_fps_time = now
          @fps_frame_count = 0
        end
      end

      def format_hz(hz)
        if hz >= 1_000_000
          format("%.2fMHz", hz / 1_000_000.0)
        elsif hz >= 1_000
          format("%.1fKHz", hz / 1_000.0)
        else
          format("%.0fHz", hz)
        end
      end

      def format_key(ascii)
        return "---" unless ascii
        return "---" if @last_key_time && (Time.now - @last_key_time) > 2.0

        case ascii
        when 0x00..0x1F
          ctrl_char = (ascii + 0x40).chr
          "^#{ctrl_char}"
        when 0x20 then "SPC"
        when 0x7F then "DEL"
        else "'#{ascii.chr}'"
        end
      end

      def disk_motor_on?
        @runner.bus.disk_controller.motor_on
      rescue
        false
      end

      def move_cursor(row, col)
        "#{ESC}[#{row};#{col}H"
      end

      def cleanup
        @runner.stop_audio if @audio_enabled
        print SHOW_CURSOR
        print NORMAL_VIDEO
        exit_row = @pad_top + DISPLAY_HEIGHT + (@debug ? 9 : 3)
        print move_cursor(exit_row, 1)
        puts "Apple ][ emulator terminated."
      end
        end
      end
    end
  end
end
