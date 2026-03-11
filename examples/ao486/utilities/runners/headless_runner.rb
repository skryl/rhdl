# frozen_string_literal: true

require_relative '../display_adapter'
require_relative 'ir_runner'
require_relative 'verilator_runner'
require_relative 'arcilator_runner'

module RHDL
  module Examples
    module AO486
      class HeadlessRunner
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

        attr_reader :runner, :mode, :sim_backend, :speed, :debug, :headless, :cycles

        def initialize(mode: DEFAULT_MODE, sim: DEFAULT_SIM, debug: false, speed: nil, headless: false, cycles: nil)
          @mode = mode.to_sym
          @sim_backend = sim&.to_sym
          @debug = !!debug
          @speed = speed
          @headless = !!headless
          @cycles = cycles
          @display_adapter = DisplayAdapter.new
          @runner = build_runner
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

        def dos_path
          @runner.dos_path
        end

        def load_bios
          @runner.load_bios
        end

        def load_dos
          @runner.load_dos
        end

        def load_bytes(base, bytes)
          @runner.load_bytes(base, bytes)
          self
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
          @display_adapter.render(
            memory: @runner.memory,
            cursor: :auto,
            debug_lines: debug ? debug_lines_for_runner : []
          )
        end

        def run
          headless ? run_headless : run_interactive
        end

        def state
          @runner.state.merge(
            mode: mode,
            effective_mode: effective_mode,
            sim_backend: sim_backend,
            speed: speed,
            debug: debug,
            headless: headless
          )
        end

        private

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

          stty_state = setup_terminal_input_mode
          print CLEAR_SCREEN if $stdout.tty?
          print HIDE_CURSOR if $stdout.tty?

          while running
            handle_keyboard_input(running_flag: -> { running = false })
            @runner.run(cycles: cycles, speed: speed, headless: false)
            if $stdout.tty?
              print MOVE_HOME
              print read_text_screen
            else
              puts read_text_screen
              break
            end
            $stdout.flush
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

        def build_runner
          case effective_mode
          when :ir
            IrRunner.new(sim: sim_backend, debug: debug, speed: speed, headless: headless, cycles: cycles)
          when :verilog
            VerilatorRunner.new(sim: sim_backend, debug: debug, speed: speed, headless: headless, cycles: cycles)
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
              "BIOS:%-3s DOS:%-3s Floppy:%s KBuf:%s",
              format_bool(snapshot[:bios_loaded]),
              format_bool(snapshot[:dos_loaded]),
              format_number(snapshot[:floppy_image_size]),
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
