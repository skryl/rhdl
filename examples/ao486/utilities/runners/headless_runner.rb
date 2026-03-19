# frozen_string_literal: true

require_relative '../display_adapter'
require_relative 'ir_runner'
require_relative 'verilator_runner'
require_relative 'arcilator_runner'
require 'rhdl/sim/native/headless_trace'

module RHDL
  module Examples
    module AO486
      class HeadlessRunner
        include RHDL::Sim::Native::HeadlessTrace
        ESC = "\e"
        CLEAR_SCREEN = "#{ESC}[2J"
        MOVE_HOME = "#{ESC}[H"
        HIDE_CURSOR = "#{ESC}[?25l"
        SHOW_CURSOR = "#{ESC}[?25h"
        FRAME_INTERVAL_SECONDS = 0.033
        DEFAULT_MODE = :ir
        DEFAULT_SIM = :compile
        UNLIMITED_CYCLES = :unlimited
        MODE_ALIASES = {
          ir: :ir,
          verilog: :verilog,
          verilator: :verilog,
          circt: :circt,
          arcilator: :circt
        }.freeze
        BACKEND_MODES = {
          verilog: :verilator,
          circt: :arcilator
        }.freeze

        attr_reader :runner, :mode, :sim_backend, :speed, :debug, :headless, :cycles, :threads

        def self.build_from_cleaned_mlir(cleaned_mlir, mode: DEFAULT_MODE, sim: DEFAULT_SIM, debug: false, speed: nil, headless: true, cycles: nil, work_dir: nil, threads: 1)
          instance = new(mode: mode, sim: sim, debug: debug, speed: speed, headless: headless, cycles: cycles, runner: nil, threads: threads)
          backend_runner = case instance.effective_mode
                           when :ir
                             IrRunner.build_from_cleaned_mlir(cleaned_mlir, backend: sim || DEFAULT_SIM)
                           when :verilog
                             raise ArgumentError, 'work_dir is required for AO486 Verilator parity runner builds' if work_dir.nil?

                             VerilatorRunner.build_from_cleaned_mlir(cleaned_mlir, work_dir: work_dir, threads: threads)
                           when :circt
                             raise ArgumentError, 'work_dir is required for AO486 Arcilator parity runner builds' if work_dir.nil?

                             ArcilatorRunner.build_from_cleaned_mlir(cleaned_mlir, work_dir: work_dir)
                           else
                             raise ArgumentError, "Unsupported AO486 mode: #{mode.inspect}"
                           end
          instance.instance_variable_set(:@runner, backend_runner)
          instance
        end

        def initialize(mode: DEFAULT_MODE, sim: DEFAULT_SIM, debug: false, speed: nil, headless: false, cycles: nil, runner: :auto, threads: 1)
          @mode = mode.to_sym
          @sim_backend = sim&.to_sym
          @debug = !!debug
          @speed = speed
          @headless = !!headless
          @cycles = cycles
          @threads = RHDL::Codegen::Verilog::VerilogSimulator.normalize_threads(threads)
          @display_adapter = DisplayAdapter.new
          @runner = runner == :auto ? build_runner : runner
        end

        def software_path(path = nil)
          base = File.expand_path('../../software', __dir__)
          return base if path.nil? || path.empty?

          File.expand_path(path, base)
        end

        def software_root
          @runner.software_root
        end

        def effective_mode
          MODE_ALIASES.fetch(mode) do
            raise ArgumentError,
                  "Unsupported AO486 mode: #{mode.inspect}. Valid public modes: ir, verilog, circt (aliases: verilator, arcilator)"
          end
        end

        def backend
          effective_mode == :ir ? sim_backend : BACKEND_MODES.fetch(effective_mode)
        end

        def bios_paths
          @runner.bios_paths
        end

        def dos_path(slot = 0)
          return @runner.dos_path if slot.to_i.zero?

          software_path('bin', "dos_slot#{slot}.img")
        end

        def dos_disk2_path
          @runner.dos_disk2_path
        end

        def hdd_path
          @runner.hdd_path
        end

        def load_hdd(path: nil)
          kwargs = {}
          kwargs[:path] = path unless path.nil?
          @runner.load_hdd(**kwargs)
          self
        end

        def load_bios
          @runner.load_bios
        end

        def load_dos(path: nil, slot: 0, activate: nil)
          kwargs = { slot: slot }
          kwargs[:path] = path unless path.nil?
          kwargs[:activate] = activate unless activate.nil?
          @runner.load_dos(**kwargs)
          self
        end

        def swap_dos(slot)
          @runner.swap_dos(slot)
          self
        end

        def load_bytes(base, bytes)
          @runner.load_bytes(base, bytes)
          self
        end

        def clear_memory!
          @runner.clear_memory! if @runner.respond_to?(:clear_memory!)
          self
        end

        def read_bytes(base, length, mapped: true)
          @runner.read_bytes(base, length, mapped: mapped)
        end

        def dump_memory(base, length, mapped: true, bytes_per_row: 16)
          @runner.dump_memory(base, length, mapped: mapped, bytes_per_row: bytes_per_row)
        end

        def memory
          @runner.memory
        end

        def sim
          @runner.sim if @runner.respond_to?(:sim)
        end

        def peek(signal_name)
          @runner.peek(signal_name)
        end

        def reset
          @runner.reset
          self
        end

        def step(cycle)
          @runner.step(cycle)
        end

        def send_keys(text)
          @runner.send_keys(text)
          self
        end

        def update_display_buffer(buffer)
          @runner.update_display_buffer(buffer)
          self
        end

        def display_buffer
          @runner.display_buffer
        end

        def render_display(debug_lines: [])
          @runner.render_display(debug_lines: Array(debug_lines) + (debug ? debug_lines_for_runner : []))
        end

        def read_text_screen
          if $stdout.tty?
            bordered_text_frame
          else
            @display_adapter.render(
              memory: @runner.memory,
              cursor: :auto,
              debug_lines: debug ? debug_lines_for_runner : []
            )
          end
        end

        def run(max_cycles: nil)
          return @runner.run(max_cycles: max_cycles) if !max_cycles.nil? && @runner.respond_to?(:run)

          headless ? run_headless : run_interactive
        end

        def run_fetch_words(max_cycles:)
          @runner.run_fetch_words(max_cycles: max_cycles)
        end

        def run_fetch_trace(max_cycles:)
          @runner.run_fetch_trace(max_cycles: max_cycles)
        end

        def run_fetch_groups(max_cycles:)
          @runner.run_fetch_groups(max_cycles: max_cycles)
        end

        def run_fetch_pc_groups(max_cycles:)
          @runner.run_fetch_pc_groups(max_cycles: max_cycles)
        end

        def run_step_trace(max_cycles:)
          @runner.run_step_trace(max_cycles: max_cycles)
        end

        def run_final_state(max_cycles:)
          @runner.run_final_state(max_cycles: max_cycles)
        end

        def final_state_snapshot
          @runner.final_state_snapshot
        end

        def last_run_stats
          @runner.last_run_stats if @runner.respond_to?(:last_run_stats)
        end

        def state
          @runner.state.merge(
            mode: mode,
            effective_mode: effective_mode,
            sim_backend: sim_backend,
            speed: speed,
            debug: debug,
            headless: headless,
            last_run_stats: last_run_stats
          )
        end

        def progress_line
          snapshot = state
          parts = ["cyc=#{snapshot[:cycles_run]}"]

          pc = snapshot[:pc]
          if pc
            parts << "pc[t/d/r/x/a]=#{%i[trace decode read execute arch].map { |key| hex(snapshot.dig(:pc, key)) }.join('/')}"
          end

          arch = snapshot[:arch]
          if arch
            regs = %i[eax ebx ecx edx esi edi esp ebp eip].map do |key|
              "#{key}=#{hex(arch[key])}"
            end
            parts << "regs=#{regs.join(',')}"
          end

          if snapshot.key?(:exception_vector) || snapshot.key?(:exception_eip)
            parts << "exc=#{hex(snapshot[:exception_vector], digits: 2)}@#{hex(snapshot[:exception_eip])}"
          end

          parts << "irq=#{hex(snapshot[:last_irq], digits: 2)}" if snapshot[:last_irq]
          parts << "intdone=#{snapshot[:interrupt_done].to_i}" if snapshot.key?(:interrupt_done)

          if (io = snapshot[:last_io])
            parts << "io=#{hex(io[:address], digits: 4)}/#{io[:length]}=#{hex(io[:data])}"
          end

          if (int13 = snapshot.dig(:dos_bridge, :int13))
            parts << "dos13=ax=#{hex(int13[:ax], digits: 4)} es:bx=#{hex(int13[:es], digits: 4)}:#{hex(int13[:bx], digits: 4)} cx=#{hex(int13[:cx], digits: 4)} dx=#{hex(int13[:dx], digits: 4)}"
          end

          parts << "shell=#{snapshot[:shell_prompt_detected] ? 1 : 0}"

          line0 = read_text_screen.lines.first.to_s.rstrip
          parts << "line0=#{line0.inspect}" unless line0.empty?

          parts.join(' ')
        end

        private

        def hex(value, digits: 8)
          return '--' if value.nil?

          format("0x%0#{digits}X", value)
        end

        def run_headless
          running = true
          trap('INT') { running = false }
          trap('TERM') { running = false }

          if resolved_run_limit == UNLIMITED_CYCLES
            @runner.run(cycles: cycles, speed: speed, headless: headless) while running
          else
            @runner.run(cycles: cycles, speed: speed, headless: headless)
          end

          state.merge(cycles: @runner.cycles_run)
        end

        def run_interactive
          running = true
          stty_state = nil

          trap('INT') { running = false }
          trap('TERM') { running = false }
          trap('WINCH') { @resize_pending = true } if Signal.list.key?('WINCH')

          @resize_pending = false
          stty_state = setup_terminal_input_mode
          update_terminal_size
          print CLEAR_SCREEN if $stdout.tty?
          print HIDE_CURSOR if $stdout.tty?

          while running
            if @resize_pending
              @resize_pending = false
              update_terminal_size
              print CLEAR_SCREEN if $stdout.tty?
            end

            handle_keyboard_input(running_flag: -> { running = false })
            @runner.run(cycles: cycles, speed: speed, headless: false)
            if $stdout.tty?
              print read_text_screen
              $stdout.flush
            else
              puts @display_adapter.render(
                memory: @runner.memory,
                cursor: :auto,
                debug_lines: debug ? debug_lines_for_runner : []
              )
              break
            end
            sleep(FRAME_INTERVAL_SECONDS)
          end

          state.merge(cycles: @runner.cycles_run)
        ensure
          restore_terminal_input_mode(stty_state)
          if $stdout.tty?
            print SHOW_CURSOR
            print "\n"
          end
        end

        def update_terminal_size
          @term_rows = DisplayAdapter::TEXT_ROWS + 8
          @term_cols = DisplayAdapter::TEXT_COLUMNS + 2
          if $stdout.respond_to?(:winsize) && $stdout.tty?
            begin
              rows, cols = $stdout.winsize
              @term_rows = [rows, @term_rows].max
              @term_cols = [cols, @term_cols].max
            rescue Errno::ENOTTY
              # Non-tty; keep defaults.
            end
          end

          debug_extra = debug ? 5 : 0
          display_height = DisplayAdapter::TEXT_ROWS + 2 + debug_extra
          display_width = DisplayAdapter::TEXT_COLUMNS + 2
          @pad_top = [(@term_rows - display_height) / 2, 0].max
          @pad_left = [(@term_cols - display_width) / 2, 0].max
        end

        def bordered_text_frame
          update_terminal_size unless @pad_top

          output = String.new
          screen_cols = DisplayAdapter::TEXT_COLUMNS
          page = @display_adapter.send(:active_page, @runner.memory)
          cursor = @display_adapter.cursor_from_bda(@runner.memory, page: page)

          output << move_cursor(@pad_top + 1, @pad_left + 1)
          output << '+' << ('-' * screen_cols) << '+'

          DisplayAdapter::TEXT_ROWS.times do |row|
            output << move_cursor(@pad_top + 2 + row, @pad_left + 1)
            line = @display_adapter.send(:render_row, @runner.memory, row, page)
            if cursor && cursor[:row] == row && cursor[:col].between?(0, screen_cols - 1)
              line[cursor[:col]] = '_'
            end
            output << '|' << line << '|'
          end

          output << move_cursor(@pad_top + 2 + DisplayAdapter::TEXT_ROWS, @pad_left + 1)
          output << '+' << ('-' * screen_cols) << '+'

          if debug
            output << render_bordered_debug_panel(screen_cols, @pad_top + 3 + DisplayAdapter::TEXT_ROWS, @pad_left + 1)
          end
          output
        end

        def render_bordered_debug_panel(width, row, col)
          lines = debug_lines_for_runner.map { |line| line.ljust(width)[0, width] }
          output = String.new
          output << move_cursor(row, col)
          output << '+' << ('-' * width) << '+'
          lines.each_with_index do |line, idx|
            output << move_cursor(row + idx + 1, col)
            output << '|' << line << '|'
          end
          output << move_cursor(row + lines.length + 1, col)
          output << '+' << ('-' * width) << '+'
          output
        end

        def move_cursor(row, col)
          "#{ESC}[#{row};#{col}H"
        end

        def build_runner
          case effective_mode
          when :ir
            IrRunner.new(sim: sim_backend, debug: debug, speed: speed, headless: headless, cycles: cycles)
          when :verilog
            VerilatorRunner.new(sim: sim_backend, debug: debug, speed: speed, headless: headless, cycles: cycles, threads: threads)
          when :circt
            ArcilatorRunner.new(sim: sim_backend, debug: debug, speed: speed, headless: headless, cycles: cycles)
          else
            raise ArgumentError,
                  "Unsupported AO486 mode: #{mode.inspect}. Valid public modes: ir, verilog, circt (aliases: verilator, arcilator)"
          end
        end

        def debug_lines_for_runner
          snapshot = state
          [
            format(
              "Mode:%-7s Backend:%-10s Cycles:%s Speed:%s",
              effective_mode.to_s.upcase,
              snapshot[:backend].to_s.upcase,
              format_number(snapshot[:cycles_run]),
              format_cycle_limit(speed)
            ),
            format(
              "BIOS:%-3s DOS:%-3s HDD:%-3s Floppy:%s Slot:%s KBuf:%s",
              format_bool(snapshot[:bios_loaded]),
              format_bool(snapshot[:dos_loaded]),
              format_bool(snapshot[:hdd_loaded]),
              format_number(snapshot[:floppy_image_size]),
              snapshot[:active_floppy_slot].nil? ? '--' : snapshot[:active_floppy_slot].to_i.to_s,
              format_number(snapshot[:keyboard_buffer_size])
            ),
            format(
              "Cursor:%02d,%02d Shell:%-3s Native:%-3s Sim:%s",
              snapshot.dig(:cursor, :row).to_i,
              snapshot.dig(:cursor, :col).to_i,
              format_bool(snapshot[:shell_prompt_detected]),
              format_bool(snapshot[:native]),
              (snapshot[:sim_backend] || snapshot[:backend]).to_s.upcase
            )
          ]
        end

        def format_number(value)
          n = value.to_i
          if n >= 1_000_000
            format('%.1fM', n / 1_000_000.0)
          elsif n >= 1_000
            format('%.1fK', n / 1_000.0)
          else
            n.to_s
          end
        end

        def format_bool(value)
          value ? 'YES' : 'NO'
        end

        def format_cycle_limit(value)
          return 'UNLIM' if resolved_run_limit == UNLIMITED_CYCLES

          format_number(value || 0)
        end

        def resolved_run_limit
          return UNLIMITED_CYCLES if cycles.nil? && speed.nil?

          cycles || speed
        end

        def handle_keyboard_input(running_flag:)
          return unless $stdin.tty?
          return unless IO.select([$stdin], nil, nil, 0)

          data = $stdin.read_nonblock(256, exception: false)
          return if data.nil? || data == :wait_readable || data.empty?

          bytes = data.bytes
          ctrl_c_index = bytes.index(3)
          if ctrl_c_index
            running_flag.call
            bytes = bytes[0...ctrl_c_index]
          end
          return if bytes.empty?

          @runner.send_keys(bytes.pack('C*'))
        rescue IO::WaitReadable, Errno::EAGAIN, EOFError
          nil
        end

        def setup_terminal_input_mode
          return nil unless $stdin.tty?

          state = `stty -g`.strip
          return nil if state.empty?

          system('stty', '-echo', '-icanon', 'min', '0', 'time', '0')
          state
        rescue StandardError
          nil
        end

        def restore_terminal_input_mode(state)
          return unless state
          return unless $stdin.tty?

          system('stty', state)
        end
      end
    end
  end
end
