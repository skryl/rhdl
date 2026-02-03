# frozen_string_literal: true

require 'io/console'
require_relative 'runner_factory'

module RHDL
  module GameBoy
    module Tasks
      # Interactive terminal-based Game Boy emulator
      # Renders the LCD display and handles keyboard input
      class CliTask
        # Game Boy screen dimensions
        SCREEN_WIDTH = 160
        SCREEN_HEIGHT = 144

        # Braille display dimensions
        LCD_CHARS_WIDE = 80   # braille chars (160 pixels / 2)
        LCD_CHARS_TALL = 36   # braille chars (144 pixels / 4)

        # ANSI escape codes
        ESC = "\e"
        CLEAR_SCREEN = "#{ESC}[2J"
        MOVE_HOME = "#{ESC}[H"
        HIDE_CURSOR = "#{ESC}[?25l"
        SHOW_CURSOR = "#{ESC}[?25h"
        REVERSE_VIDEO = "#{ESC}[7m"
        NORMAL_VIDEO = "#{ESC}[0m"
        GREEN_FG = "#{ESC}[38;2;155;188;15m"
        DARK_GREEN_FG = "#{ESC}[38;2;15;56;15m"
        BLACK_BG = "#{ESC}[40m"
        BOLD = "#{ESC}[1m"

        attr_reader :runner, :running, :options

        def initialize(options = {})
          @options = options
          @sim_mode = options[:mode] || :hdl
          @sim_backend = options[:sim] || :compile

          # Create runner using factory
          factory = RunnerFactory.new(mode: @sim_mode, backend: @sim_backend)
          @runner = factory.create
          @sim_backend = factory.backend  # May have changed due to fallback

          @sim_type = @runner.simulator_type

          @running = false
          @cycles_per_frame = options[:speed] || 100
          @debug = options[:debug] || false
          @dmg_colors = options.fetch(:dmg_colors, true)
          @audio_enabled = options[:audio] || false
          @renderer_type = options[:renderer] || :color

          # Terminal size
          @term_rows = 24
          @term_cols = 80
          @pad_top = 0
          @pad_left = 0
          @lcd_width = options[:lcd_width] || LCD_CHARS_WIDE
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

          # Input tracking
          @last_key = nil
          @last_key_time = nil

          # Keyboard mode
          @keyboard_mode = :normal
        end

        def update_terminal_size
          if $stdout.respond_to?(:winsize) && $stdout.tty?
            begin
              rows, cols = $stdout.winsize
              @term_rows = [rows, 20].max
              @term_cols = [cols, 40].max
            rescue Errno::ENOTTY
              # Not a TTY
            end
          end

          # Calculate LCD height based on renderer type
          @lcd_height = @renderer_type == :braille ? LCD_CHARS_TALL : (SCREEN_HEIGHT / 2.0).ceil

          # Calculate padding for LCD display
          lcd_height_with_debug = @lcd_height + (@debug ? 8 : 2)
          @pad_top = [(@term_rows - lcd_height_with_debug) / 2, 0].max
          @pad_left = [(@term_cols - @lcd_width) / 2, 0].max
        end

        def load_rom(path)
          puts "Loading ROM: #{path}"
          bytes = File.binread(path)
          @runner.load_rom(bytes)
          parse_rom_header(bytes)
        end

        def parse_rom_header(bytes)
          return if bytes.length < 0x150

          bytes = bytes.bytes if bytes.is_a?(String)

          title = bytes[0x134, 16].pack('C*').gsub(/\x00.*/, '').strip
          puts "  Title: #{title}"

          cart_type = bytes[0x147]
          puts "  Type: #{cart_type_name(cart_type)}"

          rom_size = 32 * (1 << bytes[0x148]) * 1024
          puts "  ROM: #{rom_size / 1024}KB"

          ram_sizes = [0, 2, 8, 32, 128, 64]
          ram_size = ram_sizes[bytes[0x149]] || 0
          puts "  RAM: #{ram_size}KB" if ram_size > 0
        end

        def cart_type_name(type)
          types = {
            0x00 => "ROM Only",
            0x01 => "MBC1",
            0x02 => "MBC1+RAM",
            0x03 => "MBC1+RAM+Battery",
            0x05 => "MBC2",
            0x06 => "MBC2+Battery",
            0x11 => "MBC3",
            0x12 => "MBC3+RAM",
            0x13 => "MBC3+RAM+Battery",
            0x19 => "MBC5",
            0x1A => "MBC5+RAM",
            0x1B => "MBC5+RAM+Battery"
          }
          types[type] || "Unknown (#{type.to_s(16)})"
        end

        def run
          @running = true

          trap('INT') { @running = false }
          trap('TERM') { @running = false }
          trap('WINCH') { update_terminal_size; print CLEAR_SCREEN }

          mode_name = "HDL (cycle-accurate)"
          puts "Starting Game Boy emulator in #{mode_name} mode..."
          puts "Backend: #{@sim_type}"
          if @audio_enabled
            puts "Audio output: #{RHDL::GameBoy::Speaker.available? ? 'enabled' : 'not available'}"
          end
          puts "WARNING: This mode is slow (for verification/testing)"
          puts "Press Ctrl+C to exit"
          sleep 1

          @runner.start_audio if @audio_enabled
          @runner.reset

          @start_time = Time.now
          @start_cycles = @runner.cycle_count
          @last_time = @start_time
          @last_cycles = @start_cycles
          @last_fps_time = @start_time
          @fps_frame_count = 0

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

        def main_loop
          @frame_count = 0

          while @running && !@runner.halted?
            frame_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            handle_keyboard_input
            @runner.run_steps(@cycles_per_frame)
            update_performance_metrics

            if @runner.screen_dirty? || @frame_count % 10 == 0
              render_screen
              @runner.clear_screen_dirty
            end

            @frame_count += 1
            @fps_frame_count += 1

            frame_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - frame_start
            sleep_time = 0.033 - frame_elapsed
            sleep(sleep_time) if sleep_time > 0
          end

          if @runner.halted?
            state = @runner.cpu_state
            halt_row = @pad_top + LCD_CHARS_TALL + (@debug ? 9 : 3)
            print move_cursor(halt_row, @pad_left + 1)
            puts "CPU HALTED at PC=$#{state[:pc].to_s(16).upcase.rjust(4, '0')}"
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
          when 65, 97, 90, 122  # A or Z - A button
            @runner.inject_key(0)
          when 83, 115, 88, 120  # S or X - B button
            @runner.inject_key(1)
          when 13, 10  # Enter - Start
            @runner.inject_key(3)
          when 127, 8  # Backspace - Select
            @runner.inject_key(2)
          end

          @last_key = ascii
          @last_key_time = Time.now
        rescue IO::WaitReadable, Errno::EAGAIN
          # No input available
        end

        def handle_escape_sequence
          if IO.select([IO.console], nil, nil, 0.05)
            begin
              seq = IO.console.read_nonblock(2)
              if @keyboard_mode == :command
                case seq
                when '[C' then @cycles_per_frame += 10
                when '[D' then @cycles_per_frame = [@cycles_per_frame - 10, 10].max
                end
              else
                case seq
                when '[A' then @runner.inject_key(6)  # Up
                when '[B' then @runner.inject_key(7)  # Down
                when '[C' then @runner.inject_key(4)  # Right
                when '[D' then @runner.inject_key(5)  # Left
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
          @keyboard_mode = @keyboard_mode == :normal ? :command : :normal if @debug
        end

        def handle_command_key(ascii)
          case ascii
          when 67, 99  # C - toggle DMG color mode
            @dmg_colors = !@dmg_colors
            print CLEAR_SCREEN
          when 82, 114  # R - toggle renderer
            @renderer_type = @renderer_type == :color ? :braille : :color
            update_terminal_size
            print CLEAR_SCREEN
          end
        end

        def render_screen
          output = String.new

          if @renderer_type == :braille
            output << GREEN_FG << BLACK_BG if @dmg_colors
            lcd_output = @runner.render_lcd_braille(chars_wide: @lcd_width, invert: false)
          else
            lcd_output = @runner.render_lcd_color(chars_wide: @lcd_width)
          end

          lcd_lines = lcd_output.split("\n")

          lcd_lines.each_with_index do |line, row|
            output << move_cursor(@pad_top + row + 1, @pad_left + 1)
            output << line
          end

          output << NORMAL_VIDEO if @dmg_colors && @renderer_type == :braille

          render_debug_window(output, lcd_lines) if @debug

          print output
        end

        def render_debug_window(output, lcd_lines)
          debug_width = @lcd_width - 2
          debug_row = @pad_top + lcd_lines.length + 2

          state = @runner.cpu_state
          kb_mode = @keyboard_mode == :command ? "CMD" : "NRM"

          line1 = format("PC:%04X A:%02X BC:%04X DE:%04X HL:%04X SP:%04X",
                         state[:pc], state[:a], state[:bc] || 0, state[:de] || 0,
                         state[:hl] || 0, state[:sp] || 0)

          line2 = format("Sim:%-10s Cyc:%s %s %.1ffps Spd:%d",
                         @sim_type.to_s, format_cycles(state[:cycles]),
                         format_hz(@current_hz), @fps, @cycles_per_frame)

          spk = @runner.speaker
          audio_status = @audio_enabled ? (spk.active? ? "PLAY" : spk.status) : "off"
          line3 = format("Key:%-3s | KB:%s | Aud:%s | Rend:%s",
                         format_key(@last_key), kb_mode, audio_status, @renderer_type)

          line4 = "ESC:cmd | R:renderer | Arrows:speed | ZXAS:ABSS"

          [line1, line2, line3, line4].each_with_index do |line, i|
            line = line.ljust(debug_width)[0, debug_width]
            output << move_cursor(debug_row + i + 1, @pad_left + 1)
            output << (i == 0 ? "+" + ("-" * debug_width) + "+" : "|" + line + "|")
          end
          output << move_cursor(debug_row + 5, @pad_left + 1)
          output << "+" << ("-" * debug_width) << "+"
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
          when 0x00..0x1F then "^#{(ascii + 0x40).chr}"
          when 0x20 then "SPC"
          when 0x7F then "DEL"
          else "'#{ascii.chr}'"
          end
        end

        def update_performance_metrics
          now = Time.now
          current_cycles = @runner.cpu_state[:cycles]

          elapsed = now - @last_time
          if elapsed >= 0.5
            @current_hz = (current_cycles - @last_cycles) / elapsed
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

        def move_cursor(row, col)
          "#{ESC}[#{row};#{col}H"
        end

        def cleanup
          @runner.stop_audio if @audio_enabled

          print SHOW_CURSOR
          print NORMAL_VIDEO
          exit_row = @pad_top + @lcd_height + (@debug ? 11 : 5)
          print move_cursor(exit_row, 1)
          puts "Game Boy emulator terminated."
        end
      end
    end
  end
end
