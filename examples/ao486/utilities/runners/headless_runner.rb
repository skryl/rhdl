# frozen_string_literal: true

require_relative '../display_adapter'
require_relative 'ir_runner'
require_relative 'verilator_runner'
require_relative 'arcilator_runner'

module RHDL
  module Examples
    module AO486
      class HeadlessRunner
        DEFAULT_MODE = :ir
        DEFAULT_SIM = :compile

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

        def backend
          mode == :ir ? sim_backend : mode
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
            cursor: @runner.cursor_position,
            debug_lines: debug ? debug_lines_for_runner : []
          )
        end

        def run
          @runner.run(cycles: cycles, speed: speed, headless: headless)
          $stdout.puts(read_text_screen) unless headless
          state.merge(cycles: @runner.cycles_run)
        end

        def run_until_shell(cycles: self.cycles)
          @runner.run_until_shell(cycles: cycles)
        end

        def state
          @runner.state.merge(
            mode: mode,
            sim_backend: sim_backend,
            speed: speed,
            debug: debug,
            headless: headless
          )
        end

        private

        def build_runner
          case mode
          when :ir
            IrRunner.new(sim: sim_backend, debug: debug, speed: speed, headless: headless, cycles: cycles)
          when :verilator
            VerilatorRunner.new(sim: sim_backend, debug: debug, speed: speed, headless: headless, cycles: cycles)
          when :arcilator
            ArcilatorRunner.new(sim: sim_backend, debug: debug, speed: speed, headless: headless, cycles: cycles)
          else
            raise ArgumentError, "Unsupported AO486 mode: #{mode.inspect}. Valid modes: ir, verilator, arcilator"
          end
        end

        def debug_lines_for_runner
          snapshot = state
          [
            "backend=#{snapshot[:mode]} sim=#{snapshot[:sim_backend]} cycles=#{snapshot[:cycles_run]} speed=#{snapshot[:speed] || 0}",
            "bios=#{snapshot[:bios_loaded]} dos=#{snapshot[:dos_loaded]} floppy_bytes=#{snapshot[:floppy_image_size]}",
            "cursor=#{snapshot.dig(:cursor, :row)},#{snapshot.dig(:cursor, :col)} keybuf=#{snapshot[:keyboard_buffer_size]} shell=#{snapshot[:shell_prompt_detected]}"
          ]
        end
      end
    end
  end
end
