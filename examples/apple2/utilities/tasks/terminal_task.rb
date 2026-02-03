# frozen_string_literal: true

# Apple II HDL Terminal Task
# Interactive terminal emulator for Apple II HDL simulation

require 'io/console'
require_relative '../runners/headless_runner'

module RHDL
  module Apple2
    module Tasks
      # Apple II Terminal class for HDL simulation
      # Supports HDL, netlist, and Verilog simulation modes
      class TerminalTask
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
          @sim_mode = options[:mode] || :hdl
          @sim_backend = options[:sim] || :ruby  # Default to :ruby for HDL mode

          # Print status for netlist mode
          if @sim_mode == :netlist
            backend_names = { interpret: "Interpreter", jit: "JIT", compile: "Compiler" }
            puts "Initializing netlist (gate-level) simulation [#{backend_names[@sim_backend]}]..."
          end

          # Create runner using HeadlessRunner factory
          @runner = HeadlessRunner.new(
            mode: @sim_mode,
            sim: @sim_backend,
            sub_cycles: options[:sub_cycles] || 14
          )

          # For compatibility
          @sim_type = @runner.simulator_type

          @running = false
          @last_screen = nil
          @cycles_per_frame = options[:speed]  # Speed is auto-adjusted based on backend
          @debug = options[:debug] || false
          @green_screen = options[:green] || false
          @hires_mode = options[:hires] || false
          @color_mode = options[:color] || false
          @audio_enabled = options[:audio] || false

          # Terminal size and padding for centering
          @term_rows = 24
          @term_cols = 80
          @pad_top = 0
          @pad_left = 0
          @hires_pad_top = 0
          @hires_pad_left = 0
          # Preferred widths (will be capped to terminal size)
          @preferred_hires_width = options[:hires_width]
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

          # Keyboard mode: :normal passes keys to emulator, :command handles runtime controls
          @keyboard_mode = :normal
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
          # Debug mode adds bordered debug window: 1 padding + 6 lines (border + 4 content + border)
          display_height = @debug ? DISPLAY_HEIGHT + 7 : DISPLAY_HEIGHT
          @pad_top = [(@term_rows - display_height) / 2, 0].max
          @pad_left = [(@term_cols - DISPLAY_WIDTH) / 2, 0].max

          # Auto-adjust hires width to fit terminal
          # Use preferred width if set, otherwise use mode-appropriate default capped to terminal
          default_width = @color_mode ? 140 : 80
          preferred = @preferred_hires_width || default_width
          @hires_width = [preferred, @term_cols].min

          # Calculate padding for hires display
          # Color mode uses half-blocks (2 pixels/char = 96 lines), braille uses 4 pixels/char (48 lines)
          hires_content_height = @color_mode ? 96 : HIRES_HEIGHT
          debug_panel_height = @debug ? 8 : 1  # 6 lines debug box + 2 gap, or 1 line for disk status
          total_content_height = hires_content_height + debug_panel_height

          if total_content_height <= @term_rows
            @hires_pad_top = [(@term_rows - total_content_height) / 2, 0].max
          else
            @hires_pad_top = @term_rows - total_content_height
          end
          @hires_pad_left = [(@term_cols - @hires_width) / 2, 0].max
        end

        def load_rom(path, base_addr: 0xD000)
          puts "Loading ROM: #{path}"
          @runner.load_rom(path, base_addr: base_addr)
        end

        def load_program(path, base_addr: 0x0800)
          puts "Loading program: #{path} at $#{base_addr.to_s(16).upcase}"
          @runner.load_program(path, base_addr: base_addr)
        end

        def load_program_bytes(bytes, base_addr: 0x0800)
          @runner.load_program_bytes(bytes, base_addr: base_addr)
        end

        def setup_reset_vector(addr)
          @runner.setup_reset_vector(addr)
        end

        def load_disk(path, drive: 0)
          puts "Loading disk image: #{path}"
          @runner.load_disk(path, drive: drive)
        end

        def load_memdump(path, pc: nil, use_appleiigo: false)
          puts "Loading memory dump: #{path}"
          @runner.load_program(path, base_addr: 0x0000)
          if pc
            puts "Setting PC to $#{pc.to_s(16).upcase}"
            if use_appleiigo
              # Load AppleIIgo ROM and patch reset vector
              create_patched_appleiigo_rom(pc)
            else
              # Create a minimal boot ROM that jumps to the desired PC
              create_boot_rom(pc)
            end
          end
        end

        def create_patched_appleiigo_rom(target_pc)
          rom_file = software_path('roms/appleiigo.rom')
          unless File.exist?(rom_file)
            puts "Warning: AppleIIgo ROM not found, using minimal boot ROM"
            return create_boot_rom(target_pc)
          end

          puts "Using AppleIIgo ROM with patched reset vector -> $#{target_pc.to_s(16).upcase}"
          rom = File.binread(rom_file).bytes

          # Patch reset vector directly to point to target_pc
          # ROM is 12K loaded at $D000, so:
          # - $FFFC (reset vector low) = offset 0x2FFC
          # - $FFFD (reset vector high) = offset 0x2FFD
          rom[0x2FFC] = target_pc & 0xFF         # low byte
          rom[0x2FFD] = (target_pc >> 8) & 0xFF  # high byte

          @runner.load_rom(rom, base_addr: 0xD000)
        end

        def create_boot_rom(target_pc)
          # Create a 12KB ROM ($D000-$FFFF) with a JMP to target_pc
          rom = Array.new(12 * 1024, 0xEA)  # Fill with NOPs

          # Put JMP target_pc at $F000 (ROM offset 0x2000)
          rom[0x2000] = 0x4C  # JMP
          rom[0x2001] = target_pc & 0xFF
          rom[0x2002] = (target_pc >> 8) & 0xFF

          # Set reset vector to $F000 (ROM offset 0x2FFC-0x2FFD)
          rom[0x2FFC] = 0x00  # Low byte of $F000
          rom[0x2FFD] = 0xF0  # High byte of $F000

          @runner.load_rom(rom, base_addr: 0xD000)
        end

        def run
          @running = true

          trap('INT') { @running = false }
          trap('TERM') { @running = false }
          trap('WINCH') { update_terminal_size; print CLEAR_SCREEN }

          mode_name = @sim_type == :netlist ? "Netlist (gate-level)" : "HDL (cycle-accurate)"
          puts "Starting Apple II emulator in #{mode_name} mode..."
          if @sim_type == :netlist
            puts "Using native Rust backend: #{@runner.native?}"
          end
          if @audio_enabled
            puts "Audio output: #{Speaker.available? ? 'enabled' : 'not available (install sox or ffmpeg)'}"
          end
          puts "WARNING: Both modes are slow (for verification/testing)"
          puts "Press Ctrl+C to exit"
          sleep 1

          # Start audio if enabled
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

        # Path to software directory
        def software_path(relative_path)
          File.expand_path("../../software/#{relative_path}", __dir__)
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

            # Sleep to maintain ~30fps display update
            frame_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - frame_start
            sleep_time = 0.033 - frame_elapsed
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

          # Handle special keys that work in all modes
          case ascii
          when 3 # Ctrl+C
            stop
            return
          when 27 # ESC - toggle command mode or check for arrow keys
            handle_escape_sequence
            return
          end

          # In command mode, handle runtime controls instead of passing to emulator
          if @keyboard_mode == :command
            handle_command_key(ascii)
            return
          end

          # Normal mode: pass key to emulator
          case ascii
          when 127, 8  # Backspace/Delete
            ascii = 0x08  # Apple II backspace
          when 10, 13  # Enter/Return
            ascii = 0x0D  # Apple II carriage return
          end

          # Convert lowercase to uppercase for Apple II
          ascii = ascii - 32 if ascii >= 97 && ascii <= 122

          # Track for debug display
          @last_key = ascii
          @last_key_time = Time.now

          # Inject the key
          @runner.inject_key(ascii)
        rescue IO::WaitReadable, Errno::EAGAIN
          # No input available
        end

        def handle_escape_sequence
          # Try to read arrow key sequence
          if IO.select([IO.console], nil, nil, 0.05)
            begin
              seq = IO.console.read_nonblock(2)
              if @keyboard_mode == :command
                # In command mode, arrow keys control speed
                speed_delta = 10
                case seq
                when '[C' # Right arrow - increase speed
                  @cycles_per_frame += speed_delta
                when '[D' # Left arrow - decrease speed
                  @cycles_per_frame = [@cycles_per_frame - speed_delta, speed_delta].max
                end
              else
                # In normal mode, arrow keys go to emulator
                case seq
                when '[A' # Up arrow
                  @runner.inject_key(0x0B) # Ctrl+K (up)
                when '[B' # Down arrow
                  @runner.inject_key(0x0A) # Ctrl+J (down)
                when '[C' # Right arrow
                  @runner.inject_key(0x15) # Ctrl+U (right)
                when '[D' # Left arrow
                  @runner.inject_key(0x08) # Ctrl+H (left/backspace)
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
          # Toggle command mode (only in debug mode)
          if @debug
            @keyboard_mode = @keyboard_mode == :normal ? :command : :normal
          else
            @runner.inject_key(0x1B)
          end
        end

        def handle_command_key(ascii)
          case ascii
          when 72, 104 # H or h - toggle hires mode
            @hires_mode = !@hires_mode
            print CLEAR_SCREEN
          when 67, 99 # C or c - toggle color mode
            @color_mode = !@color_mode
            @hires_mode = true if @color_mode  # Color implies hires
            # Recalculate width for the mode (auto-adjusts to terminal size)
            update_terminal_size
            print CLEAR_SCREEN
          end
        end

        def render_screen
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

          # Render hi-res using color or braille characters
          if @color_mode
            hires_output = @runner.render_hires_color(chars_wide: @hires_width)
          else
            hires_output = @runner.render_hires_braille(chars_wide: @hires_width, invert: true)
          end
          hires_lines = hires_output.split("\n")

          # Render each line of hires output with proper centering
          hires_lines.each_with_index do |line, row|
            output << move_cursor(@hires_pad_top + row + 1, @hires_pad_left + 1)
            output << line
          end

          output << NORMAL_VIDEO if @green_screen

          # Debug window (bordered, with padding above)
          if @debug
            debug_width = @hires_width - 2  # Account for border chars
            debug_row = @hires_pad_top + hires_lines.length + 2

            state = @runner.cpu_state
            dc = @runner.disk_controller
            kb_mode = @keyboard_mode == :command ? "CMD" : "NRM"

            # Line 1: Registers
            mode_label = @color_mode ? "[COLOR]" : "[HIRES]"
            line1 = format("PC:%04X A:%02X X:%02X Y:%02X SP:%02X P:%02X %s",
                           state[:pc], state[:a], state[:x], state[:y],
                           state[:sp], state[:p] || 0, mode_label)

            # Line 2: Sim type / cycles / speed
            line2 = format("Sim:%-7s Cyc:%s %s %.1ffps Spd:%s",
                           @sim_type.to_s.upcase,
                           format_cycles(state[:cycles]),
                           format_hz(@current_hz), @fps,
                           format_number(@cycles_per_frame))

            # Line 3: Disk / Key / keyboard mode / Audio
            spk = @runner.speaker
            audio_status = @audio_enabled ? (spk.active? ? "PLAY" : spk.status) : "off"
            line3 = format("Disk:T%02d %s|Key:%-3s|KB:%s|Aud:%s",
                           dc.track, dc.motor_on ? "ON " : "OFF",
                           format_key(@last_key),
                           kb_mode, audio_status)

            # Line 4: Help
            line4 = "ESC:cmd | H:hires | C:color | Arrows:speed"

            # Pad/truncate lines to fit within border
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
          elsif disk_motor_on?
            status_row = @hires_pad_top + hires_lines.length + 1
            output << move_cursor(status_row, @hires_pad_left + 1)
            output << "DISK LOADING..."
          end

          print output
        end

        def render_text_screen
          output = String.new
          output << move_cursor(@pad_top + 1, @pad_left + 1)
          output << GREEN_FG << BLACK_BG if @green_screen

          # Border top
          output << "+" << ("-" * SCREEN_COLS) << "+"
          output << move_cursor(@pad_top + 2, @pad_left + 1)

          # Screen content
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

          # Border bottom
          output << "+" << ("-" * SCREEN_COLS) << "+"
          output << NORMAL_VIDEO if @green_screen

          # Debug window (bordered, with padding above)
          if @debug
            debug_row = @pad_top + DISPLAY_HEIGHT + 2

            state = @runner.cpu_state
            dc = @runner.disk_controller
            kb_mode = @keyboard_mode == :command ? "CMD" : "NRM"

            # Line 1: Registers
            line1 = format("PC:%04X A:%02X X:%02X Y:%02X SP:%02X P:%02X",
                           state[:pc], state[:a], state[:x], state[:y],
                           state[:sp], state[:p] || 0)

            # Line 2: Sim type / cycles / speed
            line2 = format("Sim:%-7s Cyc:%s %s %.1ffps Spd:%s",
                           @sim_type.to_s.upcase,
                           format_cycles(state[:cycles]),
                           format_hz(@current_hz), @fps,
                           format_number(@cycles_per_frame))

            # Line 3: Disk / Key / keyboard mode / Audio
            spk = @runner.speaker
            audio_status = @audio_enabled ? (spk.active? ? "PLAY" : spk.status) : "off"
            line3 = format("Disk:T%02d %s|Key:%-3s|KB:%s|Aud:%s",
                           dc.track, dc.motor_on ? "ON " : "OFF",
                           format_key(@last_key),
                           kb_mode, audio_status)

            # Line 4: Help
            line4 = "ESC:cmd|H:hires|Arrows:spd"

            # Pad/truncate lines to fit within border
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

          # Show "DISK LOADING..." when disk motor is on (non-debug mode)
          status_row = @pad_top + DISPLAY_HEIGHT + 1
          if disk_motor_on? && !@debug
            output << move_cursor(status_row, @pad_left + 1)
            output << "DISK LOADING..."
            output << "     "  # Clear any leftover characters
          elsif !@debug
            output << move_cursor(status_row, @pad_left + 1)
            output << "                    "  # Clear the line
          end

          print output
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
          # Clear key display after 2 seconds
          return "---" if @last_key_time && (Time.now - @last_key_time) > 2.0

          case ascii
          when 0x00..0x1F
            # Control characters
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

        def disk_motor_on?
          @runner.disk_controller.motor_on
        rescue
          false
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
          # Stop audio
          @runner.stop_audio if @audio_enabled

          print SHOW_CURSOR
          print NORMAL_VIDEO
          # Position exit message below the display area
          exit_row = @pad_top + DISPLAY_HEIGHT + (@debug ? 9 : 3)
          print move_cursor(exit_row, 1)
          puts "Apple II HDL emulator terminated."
        end
      end
    end
  end
end
