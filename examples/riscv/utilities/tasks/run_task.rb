# frozen_string_literal: true

require 'io/console'

require_relative '../runners/headless_runner'

module RHDL
  module Examples
    module RISCV
      module Tasks
        # Interactive/headless runner for the RISC-V single-cycle IR harness.
        class RunTask
          ESC = "\e"
          CLEAR_SCREEN = "#{ESC}[2J"
          MOVE_HOME = "#{ESC}[H"
          HIDE_CURSOR = "#{ESC}[?25l"
          SHOW_CURSOR = "#{ESC}[?25h"
          FRAME_INTERVAL_SECONDS = 0.033
          MAX_WORK_SLICE_SECONDS = 0.020
          MAX_BUDGET_FRAMES = 8

          DEFAULT_MMAP_START = 0x0000_0000
          DEFAULT_MMAP_WIDTH = 80
          DEFAULT_MMAP_HEIGHT = 24
          DEFAULT_MMAP_ROW_STRIDE = 80
          DEFAULT_UART_WIDTH = 80
          DEFAULT_UART_HEIGHT = 24
          XV6_RESET_PC = 0x8000_0000

          attr_reader :cpu, :runner, :options

          def initialize(options = {})
            @options = options
            @mode = (options[:mode] || :ir).to_sym
            @sim_backend = (options[:sim] || default_sim_backend(@mode)).to_sym
            @io_mode = (options[:io] || :mmap).to_sym
            @debug = !!options[:debug]
            @cycles_per_frame = [options[:speed].to_i, 1].max
            @headless = !!options[:headless]
            @headless_cycles = options[:cycles].to_i if options[:cycles]

            @mmap_start = integer_option(options[:mmap_start], DEFAULT_MMAP_START)
            @mmap_width = [integer_option(options[:mmap_width], DEFAULT_MMAP_WIDTH), 1].max
            @mmap_height = [integer_option(options[:mmap_height], DEFAULT_MMAP_HEIGHT), 1].max
            @mmap_row_stride = [integer_option(options[:mmap_stride], DEFAULT_MMAP_ROW_STRIDE), 1].max

            @uart_width = [integer_option(options[:uart_width], DEFAULT_UART_WIDTH), 1].max
            @uart_height = [integer_option(options[:uart_height], DEFAULT_UART_HEIGHT), 1].max

            @running = false
            @last_uart_len = 0
            @last_mmap_frame = nil
            @keyboard_mode = :normal
            @last_key = nil
            @last_key_time = nil
            @resize_pending = false
            @term_rows = 24
            @term_cols = 80
            @pad_top = 0
            @pad_left = 0

            @uart_cells = Array.new(@uart_height) { Array.new(@uart_width, ' ') }
            @uart_row = 0
            @uart_col = 0

            @start_time = nil
            @last_perf_time = nil
            @last_perf_cycles = 0
            @current_hz = 0.0
            @fps = 0.0
            @fps_frame_count = 0
            @last_fps_time = nil
            @cycle_budget = 0
            @stty_state = nil

            @runner = HeadlessRunner.new(mode: @mode, sim: @sim_backend)
            @cpu = @runner.cpu
            @cycle_chunk = default_cycle_chunk
            update_terminal_size
          end

          def software_path(path = nil)
            base = File.expand_path('../../software', __dir__)
            return base if path.nil? || path.empty?

            File.expand_path(path, base)
          end

          def load_program(path, base_addr: 0)
            bytes = File.binread(path)
            load_program_bytes(bytes, base_addr: base_addr)
          end

          def load_program_bytes(bytes, base_addr: 0)
            @runner.load_program_bytes(bytes, base_addr: base_addr)
          end

          def load_xv6(kernel:, fs:, pc: XV6_RESET_PC)
            @runner.load_xv6(kernel: kernel, fs: fs, pc: pc)
          end

          def set_pc(value)
            @runner.set_pc(value)
          end

          def run
            trap('INT') { @running = false }
            trap('TERM') { @running = false }

            @running = true
            @headless ? run_headless : run_interactive
          ensure
            print "\n" if @io_mode == :uart
          end

          private

          def run_headless
            initialize_performance_metrics
            cycles = @headless_cycles || @cycles_per_frame
            @cpu.run_cycles(cycles)
            update_performance_metrics

            if @io_mode == :uart
              consume_uart_output
              puts uart_text_frame
            else
              render_mmap_frame(force: true)
            end

            @cpu.state
          end

          def run_interactive
            puts startup_banner
            puts 'Press Ctrl+C to exit.'
            puts 'Debug mode enabled.' if @debug
            puts 'ESC toggles command mode when debug is enabled.' if @debug

            trap('WINCH') { @resize_pending = true }
            setup_terminal_input_mode

            print CLEAR_SCREEN if $stdout.tty?
            print HIDE_CURSOR if $stdout.tty?
            main_loop
          ensure
            cleanup_terminal
          end

          def main_loop
            initialize_performance_metrics

            while @running
              if @resize_pending
                @resize_pending = false
                update_terminal_size
                print CLEAR_SCREEN if $stdout.tty?
              end

              frame_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              handle_keyboard_input
              run_cpu_budgeted(frame_start)
              update_performance_metrics

              if @io_mode == :uart
                consume_uart_output
                render_uart_frame
              else
                render_mmap_frame
              end

              frame_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - frame_start
              sleep_time = FRAME_INTERVAL_SECONDS - frame_elapsed
              sleep(sleep_time) if sleep_time > 0
            end
          end

          def run_cpu_budgeted(frame_start)
            max_budget = [@cycles_per_frame * MAX_BUDGET_FRAMES, @cycles_per_frame].max
            @cycle_budget = [@cycle_budget + @cycles_per_frame, max_budget].min
            return if @cycle_budget <= 0

            while @running && @cycle_budget > 0
              step_cycles = [@cycle_budget, @cycle_chunk].min
              @cpu.run_cycles(step_cycles)
              @cycle_budget -= step_cycles

              elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - frame_start
              break if elapsed >= MAX_WORK_SLICE_SECONDS
            end
          end

          def handle_keyboard_input
            return unless IO.select([$stdin], nil, nil, 0)

            data = $stdin.read_nonblock(256, exception: false)
            return if data.nil? || data.empty? || data == :wait_readable

            bytes = data.bytes
            idx = 0
            while idx < bytes.length
              byte = bytes[idx] & 0xFF

              if byte == 3 # Ctrl+C
                @running = false
                break
              end

              if byte == 27 # ESC
                consumed = handle_escape_bytes(bytes[(idx + 1), 2] || [])
                idx += (consumed + 1)
                next
              end

              if @keyboard_mode == :command
                handle_command_key(byte)
              elsif @io_mode == :uart
                mapped = process_input_bytes([byte])
                @last_key = mapped.first
                @last_key_time = Time.now
                @cpu.uart_receive_bytes(mapped) unless mapped.empty?
              end

              idx += 1
            end
          rescue IO::WaitReadable, Errno::EAGAIN
            nil
          rescue EOFError
            nil
          end

          def handle_escape_bytes(bytes)
            seq = bytes.pack('C*')
            if seq.length >= 2 && seq.start_with?('[')
              handle_esc_sequence_bytes(seq[0, 2].bytes)
              return 2
            end

            handle_esc_key
            0
          end

          def handle_esc_sequence_bytes(bytes)
            if @keyboard_mode == :command
              speed_delta = [@cycles_per_frame / 10, 1].max
              case bytes.pack('C*')
              when '[C'
                @cycles_per_frame += speed_delta
              when '[D'
                @cycles_per_frame = [@cycles_per_frame - speed_delta, 1].max
              end
            elsif @io_mode == :uart
              @cpu.uart_receive_byte(0x1B)
              @cpu.uart_receive_bytes(bytes)
            end
          end

          def handle_esc_key
            if @debug
              @keyboard_mode = (@keyboard_mode == :normal ? :command : :normal)
            elsif @io_mode == :uart
              @cpu.uart_receive_byte(0x1B)
            end
          end

          def handle_command_key(ascii)
            case ascii
            when 43, 61 # + or =
              @cycles_per_frame += [@cycles_per_frame / 10, 1].max
            when 45, 95 # - or _
              @cycles_per_frame = [@cycles_per_frame - [@cycles_per_frame / 10, 1].max, 1].max
            when 67, 99 # C/c
              clear_uart_screen
            when 81, 113 # Q/q
              @running = false
            end
          end

          def process_input_bytes(bytes)
            raw = bytes.map { |b| b.to_i & 0xFF }
            return [] if raw.empty?

            # Even in canonical mode, some terminals may pass Ctrl+C bytes.
            ctrl_c_index = raw.index(3)
            if ctrl_c_index
              @running = false
              raw = raw[0...ctrl_c_index]
            end

            normalize_input_bytes(raw)
          end

          def normalize_input_bytes(data)
            data.map do |byte|
              case byte
              when 13 then 10
              when 127 then 8
              else byte & 0xFF
              end
            end
          end

          def render_mmap_frame(force: false)
            text = mmap_text_frame
            return if !force && text == @last_mmap_frame

            @last_mmap_frame = text
            if $stdout.tty?
              print MOVE_HOME
              print text
              $stdout.flush
            else
              puts text
            end
          end

          def render_uart_frame
            frame = uart_text_frame
            if $stdout.tty?
              print MOVE_HOME
              print frame
              $stdout.flush
            else
              puts frame
            end
          end

          def uart_text_frame
            output = String.new
            screen_cols = @uart_width
            output << move_cursor(@pad_top + 1, @pad_left + 1)
            output << "+" << ("-" * screen_cols) << "+"
            output << move_cursor(@pad_top + 2, @pad_left + 1)

            @uart_cells.each_with_index do |row_chars, row|
              output << "|"
              output << row_chars.join
              output << "|"
              output << move_cursor(@pad_top + 3 + row, @pad_left + 1)
            end

            output << "+" << ("-" * screen_cols) << "+"
            if @debug
              output << render_debug_panel(screen_cols, @pad_top + @uart_height + 3, @pad_left + 1)
            else
              output << move_cursor(@pad_top + @uart_height + 3, @pad_left + 1)
              output << status_line_for_non_debug(screen_cols)
            end
            output
          end

          def mmap_text_frame
            len = @mmap_row_stride * @mmap_height
            bytes = read_mapped_bytes(@mmap_start, len)

            header = format(
              "RISC-V MMAP View  pc=0x%08x cycles=%d base=0x%08x\n",
              @cpu.read_pc,
              @cpu.clock_count,
              @mmap_start
            )

            body = Array.new(@mmap_height) do |row|
              row_base = row * @mmap_row_stride
              row_bytes = bytes[row_base, @mmap_width] || []
              row_bytes.map { |b| printable_char(b) }.join
            end.join("\n")

            frame = +"#{header}#{body}\n"
            frame << debug_panel_text if @debug
            frame
          end

          def debug_panel_text
            debug_width = [@mmap_width, 72].max
            lines = current_debug_lines.map { |line| line.ljust(debug_width)[0, debug_width] }
            panel = +"+" << ("-" * debug_width) << "+\n"
            lines.each { |line| panel << "|" << line << "|\n" }
            panel << "+" << ("-" * debug_width) << "+\n"
            panel
          end

          def render_debug_panel(width, row, col)
            lines = current_debug_lines.map { |line| line.ljust(width)[0, width] }
            output = String.new
            output << move_cursor(row, col)
            output << "+" << ("-" * width) << "+"
            lines.each_with_index do |line, idx|
              output << move_cursor(row + idx + 1, col)
              output << "|" << line << "|"
            end
            output << move_cursor(row + lines.length + 1, col)
            output << "+" << ("-" * width) << "+"
            output
          end

          def printable_char(byte)
            value = byte.to_i & 0xFF
            (32..126).include?(value) ? value.chr : '.'
          end

          def read_mapped_bytes(offset, length)
            if @cpu.native? && @cpu.sim.respond_to?(:runner_read_memory)
              @cpu.sim.runner_read_memory(offset.to_i, length.to_i, mapped: true)
            else
              read_data_bytes(offset, length)
            end
          end

          def read_data_bytes(offset, length)
            result = []
            addr = offset.to_i

            while result.length < length
              word = @cpu.read_data_word(addr)
              4.times do |i|
                result << ((word >> (8 * i)) & 0xFF)
                break if result.length >= length
              end
              addr += 4
            end

            result
          end

          def consume_uart_output
            bytes = @cpu.uart_tx_bytes
            return if bytes.length <= @last_uart_len

            delta = bytes[@last_uart_len..] || []
            @last_uart_len = bytes.length
            apply_uart_bytes(delta)
          end

          def apply_uart_bytes(bytes)
            bytes.each { |byte| apply_uart_byte(byte.to_i & 0xFF) }
          end

          def apply_uart_byte(byte)
            case byte
            when 0x0A # \n
              @uart_row += 1
              @uart_col = 0
            when 0x0D # \r
              @uart_col = 0
            when 0x08 # backspace
              @uart_col = [@uart_col - 1, 0].max
            when 0x09 # tab
              next_col = ((@uart_col / 8) + 1) * 8
              @uart_col = [next_col, @uart_width - 1].min
            when 0x20..0x7E
              @uart_cells[@uart_row][@uart_col] = byte.chr
              @uart_col += 1
            end

            if @uart_col >= @uart_width
              @uart_col = 0
              @uart_row += 1
            end

            scroll_uart_if_needed
          end

          def scroll_uart_if_needed
            while @uart_row >= @uart_height
              @uart_cells.shift
              @uart_cells << Array.new(@uart_width, ' ')
              @uart_row -= 1
            end
          end

          def clear_uart_screen
            @uart_cells.each { |row| row.fill(' ') }
            @uart_row = 0
            @uart_col = 0
          end

          def integer_option(value, fallback)
            return fallback if value.nil?

            value.to_i
          end

          def update_terminal_size
            if $stdout.respond_to?(:winsize) && $stdout.tty?
              begin
                rows, cols = $stdout.winsize
                @term_rows = [rows, @uart_height + 8].max
                @term_cols = [cols, @uart_width + 2].max
              rescue Errno::ENOTTY
                # Non-tty; keep defaults.
              end
            end

            display_height = @uart_height + (@debug ? 8 : 3)
            display_width = @uart_width + 2
            @pad_top = [(@term_rows - display_height) / 2, 0].max
            @pad_left = [(@term_cols - display_width) / 2, 0].max
          end

          def initialize_performance_metrics
            now = Time.now
            @start_time = now
            @last_perf_time = now
            @last_perf_cycles = @cpu.clock_count
            @current_hz = 0.0
            @fps = 0.0
            @fps_frame_count = 0
            @last_fps_time = now
          end

          def update_performance_metrics
            now = Time.now
            current_cycles = @cpu.clock_count
            elapsed = now - @last_perf_time
            if elapsed >= 0.5
              @current_hz = (current_cycles - @last_perf_cycles) / elapsed
              @last_perf_time = now
              @last_perf_cycles = current_cycles
            end

            @fps_frame_count += 1
            fps_elapsed = now - @last_fps_time
            if fps_elapsed >= 1.0
              @fps = @fps_frame_count / fps_elapsed
              @fps_frame_count = 0
              @last_fps_time = now
            end
          end

          def current_debug_lines
            state = @cpu.state
            sim_label = begin
              @cpu.simulator_type.to_s.upcase
            rescue StandardError
              @sim_backend.to_s.upcase
            end

            [
              format("PC:%08X INST:%08X X1:%08X X2:%08X",
                     state[:pc], state[:inst], state[:x1], state[:x2]),
              format("X10:%08X X11:%08X Cycles:%s",
                     state[:x10], state[:x11], format_number(state[:cycles])),
              format("Sim:%-10s Mode:%s IO:%s Speed:%s %s %.1ffps",
                     sim_label,
                     @mode.to_s.upcase,
                     @io_mode.to_s.upcase,
                     format_number(@cycles_per_frame),
                     format_hz(@current_hz),
                     @fps),
              format("KB:%s Key:%s ESC:cmd +/-:speed C:clear Q:quit",
                     (@keyboard_mode == :command ? 'CMD' : 'NRM'),
                     format_key(@last_key))
            ]
          end

          def status_line_for_non_debug(width)
            line = format("PC:%08X Cycles:%s  Ctrl+C:exit",
                          @cpu.read_pc,
                          format_number(@cpu.clock_count))
            line.ljust(width)[0, width]
          end

          def format_key(ascii)
            return '---' unless ascii
            return '---' if @last_key_time && (Time.now - @last_key_time) > 2.0

            case ascii
            when 0x00..0x1F
              "^#{(ascii + 0x40).chr}"
            when 0x20
              'SPC'
            when 0x7F
              'DEL'
            else
              "'#{ascii.chr}'"
            end
          end

          def move_cursor(row, col)
            "#{ESC}[#{row};#{col}H"
          end

          def cleanup_terminal
            restore_terminal_input_mode
            return unless $stdout.tty?

            print SHOW_CURSOR
            print "\n"
          end

          def setup_terminal_input_mode
            return unless $stdin.tty?

            state = `stty -g`.strip
            return if state.empty?

            @stty_state = state
            # Non-canonical char-at-a-time input with signals still enabled.
            system('stty', '-echo', '-icanon', 'min', '0', 'time', '0')
          rescue StandardError
            @stty_state = nil
          end

          def restore_terminal_input_mode
            return unless @stty_state
            return unless $stdin.tty?

            system('stty', @stty_state)
          ensure
            @stty_state = nil
          end

          def default_cycle_chunk
            backend = if @runner.respond_to?(:backend)
                        @runner.backend
                      else
                        @sim_backend
                      end

            case backend
            when :interpreter, :interpret
              1_000
            when :jit
              50_000
            when :compiler, :compile
              100_000
            else
              5_000
            end
          end

          def format_number(value)
            n = value.to_i
            if n >= 1_000_000
              format("%.1fM", n / 1_000_000.0)
            elsif n >= 1_000
              format("%.1fK", n / 1_000.0)
            else
              n.to_s
            end
          end

          def format_hz(hz)
            value = hz.to_f
            if value >= 1_000_000
              format("%.2fMHz", value / 1_000_000.0)
            elsif value >= 1_000
              format("%.1fKHz", value / 1_000.0)
            else
              format("%.0fHz", value)
            end
          end

          def default_sim_backend(mode)
            case mode
            when :ruby
              :ruby
            when :ir, :netlist
              :compile
            when :verilog
              :ruby
            else
              :compile
            end
          end

          def startup_banner
            backend = @runner.respond_to?(:backend) ? @runner.backend : @sim_backend
            mode_label = @runner.respond_to?(:effective_mode) ? @runner.effective_mode : @mode
            "Starting RISC-V core [mode=#{mode_label}, sim=#{@sim_backend}, backend=#{backend}, io=#{@io_mode}, debug=#{@debug}]"
          end
        end
      end
    end
  end
end
