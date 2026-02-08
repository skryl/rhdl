# frozen_string_literal: true

require 'io/console'
require 'optparse'

module RHDL
  module Examples
    module GameBoy
      module Tasks
        # Base class for Game Boy tasks
      class Task
        attr_reader :options

        def initialize(options = {})
          @options = options
        end

        def run
          raise NotImplementedError, "#{self.class} must implement #run"
        end

        protected

        def puts_status(status, message)
          puts "  [#{status}] #{message}"
        end

        def puts_ok(message)
          puts_status('OK', message)
        end

        def puts_error(message)
          puts_status('ERROR', message)
        end

        def puts_header(title)
          puts title
          puts '=' * 50
          puts
        end
      end

      # Task for running the Game Boy emulator
      # Supports both headless and interactive terminal modes
      class RunTask < Task
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

        attr_reader :runner, :running

        def run
          if options[:headless]
            run_headless
          else
            run_interactive
          end
        end

        # Run the emulator in headless mode (no terminal UI)
        def run_headless
          initialize_runner
          load_rom_from_options
          @runner.reset

          cycles = options[:cycles] || 1000
          @runner.run_steps(cycles)

          @runner.cpu_state
        end

        # Run the emulator in interactive terminal mode
        def run_interactive
          initialize_runner
          initialize_terminal_state

          load_rom_from_options
          run_terminal
        end

        # Create demo ROM bytes
        def self.create_demo_rom
          rom = Array.new(32 * 1024, 0)

          # Nintendo logo at 0x104 (required for boot)
          nintendo_logo = [
            0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
            0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
            0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
            0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
            0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
            0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
          ]
          nintendo_logo.each_with_index { |b, i| rom[0x104 + i] = b }

          # Title at 0x134
          "RHDL TEST".bytes.each_with_index { |b, i| rom[0x134 + i] = b }

          # Header checksum at 0x14D
          checksum = 0
          (0x134...0x14D).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
          rom[0x14D] = checksum

          # Entry point at 0x100 - NOP JP 0x150
          # Game Boy entry point is 4 bytes (0x100-0x103), followed by Nintendo logo at 0x104
          rom[0x100] = 0x00  # NOP
          rom[0x101] = 0xC3  # JP
          rom[0x102] = 0x50  # addr low (0x0150)
          rom[0x103] = 0x01  # addr high

          # Main program at 0x150
          pc = 0x150

          # Turn on LCD
          rom[pc] = 0x3E; pc += 1  # LD A, $91
          rom[pc] = 0x91; pc += 1
          rom[pc] = 0xE0; pc += 1  # LDH ($40), A
          rom[pc] = 0x40; pc += 1

          # Infinite loop
          loop_addr = pc
          rom[pc] = 0x00; pc += 1  # NOP
          rom[pc] = 0x18; pc += 1  # JR loop
          rom[pc] = (loop_addr - pc - 1) & 0xFF

          rom.pack('C*')
        end

        private

        def initialize_runner
          require_relative '../runners/headless_runner'

          mode = options[:mode] || :hdl
          sim = options[:sim] || :compile

          @runner = HeadlessRunner.new(mode: mode, sim: sim)
        end

        def initialize_terminal_state
          @running = false
          @cycles_per_frame = options[:speed] || default_cycles_per_frame
          @debug = options[:debug] || false
          @dmg_colors = options[:dmg_colors] != false
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
          @pressed_keys = {}
          @key_hold_seconds = 0.08

          # Keyboard mode
          @keyboard_mode = :normal
        end

        def load_rom_from_options
          if options[:rom_file]
            load_rom(options[:rom_file])
          elsif options[:rom_bytes]
            @runner.load_rom(options[:rom_bytes])
          elsif options[:pop]
            pop_rom = File.expand_path('../../software/roms/pop.gb', __dir__)
            raise "Prince of Persia ROM not found: #{pop_rom}" unless File.exist?(pop_rom)

            puts "Loading Prince of Persia..."
            load_rom(pop_rom)
          elsif options[:demo]
            puts "Loading demo ROM..."
            @runner.load_rom(self.class.create_demo_rom)
          else
            raise ArgumentError, "No ROM specified. Use --demo, --pop, or provide a ROM file."
          end
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

        def default_cycles_per_frame
          mode = options[:mode] || :hdl
          sim = options[:sim] || :compile

          return 70_224 if mode == :verilog

          case sim
          when :compile, :jit
            70_224
          when :interpret
            10_000
          else
            100
          end
        end

        def run_terminal
          @running = true

          trap('INT') { @running = false }
          trap('TERM') { @running = false }
          trap('WINCH') { update_terminal_size; print CLEAR_SCREEN }

          mode_name = "HDL (cycle-accurate)"
          puts "Starting Game Boy emulator in #{mode_name} mode..."
          puts "Backend: #{@runner.simulator_type}"
          if @audio_enabled && defined?(Speaker)
            puts "Audio output: #{Speaker.available? ? 'enabled' : 'not available'}"
          end
          puts "WARNING: This mode is slow (for verification/testing)"
          puts "Press Ctrl+C to exit"
          sleep 1

          @runner.runner.start_audio if @audio_enabled && @runner.runner.respond_to?(:start_audio)

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

        def main_loop
          @frame_count = 0

          while @running && !@runner.halted?
            frame_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            handle_keyboard_input
            release_expired_keys
            run_until_next_display_frame
            update_performance_metrics

            if screen_dirty? || @frame_count % 10 == 0
              render_screen
              clear_screen_dirty
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

        def screen_dirty?
          @runner.runner.respond_to?(:screen_dirty?) ? @runner.runner.screen_dirty? : true
        end

        def clear_screen_dirty
          @runner.runner.clear_screen_dirty if @runner.runner.respond_to?(:clear_screen_dirty)
        end

        def run_until_next_display_frame
          return @runner.run_steps(@cycles_per_frame) unless @runner.respond_to?(:frame_count)

          start_frame = @runner.frame_count
          return @runner.run_steps(@cycles_per_frame) unless start_frame

          # Advance in chunks until at least one complete LCD frame is produced.
          # This avoids sampling partially updated framebuffers when cadence drifts.
          chunk = [@cycles_per_frame / 8, 1000].max
          max_chunks = 256
          chunks = 0

          while @runner.frame_count == start_frame && chunks < max_chunks
            @runner.run_steps(chunk)
            chunks += 1
          end

          # Fallback for cores that temporarily stop frame signaling.
          @runner.run_steps(@cycles_per_frame) if chunks >= max_chunks
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

          @lcd_height = @renderer_type == :braille ? LCD_CHARS_TALL : (SCREEN_HEIGHT / 2.0).ceil
          lcd_height_with_debug = @lcd_height + (@debug ? 8 : 2)
          @pad_top = [(@term_rows - lcd_height_with_debug) / 2, 0].max
          @pad_left = [(@term_cols - @lcd_width) / 2, 0].max
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
          when 90, 122  # Z - A button
            inject_key(4)
          when 88, 120  # X - B button
            inject_key(5)
          when 65, 97, 127, 8  # A / Backspace - Select
            inject_key(6)
          when 83, 115, 13, 10, 32  # S / Enter / Space - Start
            inject_key(7)
          end

          @last_key = ascii
          @last_key_time = Time.now
        rescue IO::WaitReadable, Errno::EAGAIN
          # No input available
        end

        def inject_key(bit)
          return unless @runner.runner.respond_to?(:inject_key)

          @runner.runner.inject_key(bit)
          @pressed_keys[bit] = Time.now + @key_hold_seconds
        end

        def release_key(bit)
          return unless @runner.runner.respond_to?(:release_key)

          @runner.runner.release_key(bit)
          @pressed_keys.delete(bit)
        end

        def release_expired_keys
          return if @pressed_keys.empty?

          now = Time.now
          @pressed_keys.keys.each do |bit|
            release_key(bit) if now >= @pressed_keys[bit]
          end
        end

        def handle_escape_sequence
          if IO.select([IO.console], nil, nil, 0.05)
            begin
              seq = IO.console.read_nonblock(2)
              if @keyboard_mode == :command
                case seq
                when '[C'  # Right - increase speed
                  @cycles_per_frame += 10
                when '[D'  # Left - decrease speed
                  @cycles_per_frame = [@cycles_per_frame - 10, 10].max
                end
              else
                case seq
                when '[A'  # Up
                  inject_key(2)
                when '[B'  # Down
                  inject_key(3)
                when '[C'  # Right
                  inject_key(0)
                when '[D'  # Left
                  inject_key(1)
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
            if @dmg_colors
              output << GREEN_FG
              output << BLACK_BG
            end
            lcd_output = render_lcd_braille(chars_wide: @lcd_width, invert: false)
          else
            lcd_output = render_lcd_color(chars_wide: @lcd_width)
          end

          lcd_lines = lcd_output.split("\n")

          lcd_lines.each_with_index do |line, row|
            output << move_cursor(@pad_top + row + 1, @pad_left + 1)
            output << line
          end

          output << NORMAL_VIDEO if @dmg_colors && @renderer_type == :braille

          if @debug
            debug_width = @lcd_width - 2
            debug_row = @pad_top + lcd_lines.length + 2

            state = @runner.cpu_state
            kb_mode = @keyboard_mode == :command ? "CMD" : "NRM"

            line1 = format("PC:%04X A:%02X BC:%04X DE:%04X HL:%04X SP:%04X",
                           state[:pc], state[:a], state[:bc] || 0, state[:de] || 0,
                           state[:hl] || 0, state[:sp] || 0)

            line2 = format("Sim:%-10s Cyc:%s %s %.1ffps Spd:%d",
                           @runner.simulator_type.to_s, format_cycles(state[:cycles]),
                           format_hz(@current_hz), @fps, @cycles_per_frame)

            spk = @runner.runner.respond_to?(:speaker) ? @runner.runner.speaker : nil
            audio_status = @audio_enabled && spk ? (spk.active? ? "PLAY" : spk.status) : "off"
            line3 = format("Key:%-3s | KB:%s | Aud:%s | Rend:%s",
                           format_key(@last_key), kb_mode, audio_status, @renderer_type)

            line4 = "ESC:cmd | R:renderer | Arrows:speed | Z: A X: B A:Sel S:Sta"

            line1 = line1.ljust(debug_width)[0, debug_width]
            line2 = line2.ljust(debug_width)[0, debug_width]
            line3 = line3.ljust(debug_width)[0, debug_width]
            line4 = line4.ljust(debug_width)[0, debug_width]

            output << move_cursor(debug_row, @pad_left + 1)
            output << "+" << ("-" * debug_width) << "+"
            output << move_cursor(debug_row + 1, @pad_left + 1)
            output << "|" << line1 << "|"
            output << move_cursor(debug_row + 2, @pad_left + 1)
            output << "|" << line2 << "|"
            output << move_cursor(debug_row + 3, @pad_left + 1)
            output << "|" << line3 << "|"
            output << move_cursor(debug_row + 4, @pad_left + 1)
            output << "|" << line4 << "|"
            output << move_cursor(debug_row + 5, @pad_left + 1)
            output << "+" << ("-" * debug_width) << "+"
          end

          print output
        end

        def render_lcd_braille(chars_wide:, invert: false)
          if @runner.runner.respond_to?(:render_lcd_braille)
            @runner.runner.render_lcd_braille(chars_wide: chars_wide, invert: invert)
          else
            # Fallback empty screen
            Array.new(LCD_CHARS_TALL) { " " * chars_wide }.join("\n")
          end
        end

        def render_lcd_color(chars_wide:)
          if @runner.runner.respond_to?(:render_lcd_color)
            @runner.runner.render_lcd_color(chars_wide: chars_wide)
          else
            # Fallback empty screen
            Array.new(SCREEN_HEIGHT / 2) { " " * chars_wide }.join("\n")
          end
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
          when 0x00..0x1F
            ctrl_char = (ascii + 0x40).chr
            "^#{ctrl_char}"
          when 0x20
            "SPC"
          when 0x7F
            "DEL"
          else
            "'#{ascii.chr}'"
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

        def move_cursor(row, col)
          "#{ESC}[#{row};#{col}H"
        end

        def cleanup
          @pressed_keys.keys.each { |bit| release_key(bit) } unless @pressed_keys.nil?

          if @audio_enabled && @runner.runner.respond_to?(:stop_audio)
            @runner.runner.stop_audio
          end

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
end
