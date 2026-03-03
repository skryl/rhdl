# frozen_string_literal: true

require_relative "ir_runner"
require_relative "verilator_runner"
require_relative "arcilator_runner"

module RHDL
  module Examples
    module AO486
      class HeadlessRunner
        attr_reader :runner, :mode

        def initialize(mode:, source_mode: :generated, **kwargs)
          @mode = mode.to_sym
          @runner = case @mode
                    when :ir
                      IrRunner.new(**kwargs)
                    when :verilator
                      VerilatorRunner.new(source_mode: source_mode, **kwargs)
                    when :arcilator
                      ArcilatorRunner.new(**kwargs)
                    else
                      raise ArgumentError, "unknown mode #{@mode.inspect}; expected :ir, :verilator, or :arcilator"
                    end
        end

        def run_program(**kwargs)
          runner.run_program(**kwargs)
        end

        def run_dos_boot(**kwargs)
          unless runner.respond_to?(:run_dos_boot)
            raise NotImplementedError, "#{runner.class} does not implement #run_dos_boot"
          end

          runner.run_dos_boot(**kwargs)
        end

        def supports_live_cycles?
          return false unless runner.respond_to?(:supports_live_cycles?)

          !!runner.supports_live_cycles?
        end

        def load_program(**kwargs)
          unless runner.respond_to?(:load_program)
            raise NotImplementedError, "#{runner.class} does not implement #load_program"
          end

          runner.load_program(**kwargs)
        end

        def load_dos_boot(**kwargs)
          unless runner.respond_to?(:load_dos_boot)
            raise NotImplementedError, "#{runner.class} does not implement #load_dos_boot"
          end

          runner.load_dos_boot(**kwargs)
        end

        def reset!
          unless runner.respond_to?(:reset!)
            raise NotImplementedError, "#{runner.class} does not implement #reset!"
          end

          runner.reset!
        end

        def run_cycles(cycles)
          unless runner.respond_to?(:run_cycles)
            raise NotImplementedError, "#{runner.class} does not implement #run_cycles"
          end

          runner.run_cycles(cycles)
        end

        def state
          unless runner.respond_to?(:state)
            raise NotImplementedError, "#{runner.class} does not implement #state"
          end

          runner.state
        end

        def send_keyboard_bytes(bytes)
          return false unless runner.respond_to?(:send_keyboard_bytes)

          runner.send_keyboard_bytes(bytes)
        end
      end
    end
  end
end
