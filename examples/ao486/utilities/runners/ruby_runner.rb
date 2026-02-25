# frozen_string_literal: true

require_relative '../../hdl/harness'

module RHDL
  module Examples
    module AO486
      # Ruby simulation runner for ao486.
      # Wraps the Harness class with a CLI-friendly interface.
      class RubyRunner
        attr_reader :harness

        def initialize
          @harness = Harness.new
        end

        def load_com(bytes)
          @harness.load_com(bytes)
        end

        def load_at(addr, bytes)
          @harness.load_at(addr, bytes)
        end

        def run(max_steps: 100_000)
          @harness.run(max_steps: max_steps)
        end

        def step
          @harness.step
        end

        def state
          @harness.state
        end

        def reg(name)
          @harness.reg(name)
        end

        def set_reg(name, value)
          @harness.set_reg(name, value)
        end

        def on_io_write(&block)
          @harness.on_io_write(&block)
        end

        def on_io_read(&block)
          @harness.on_io_read(&block)
        end

        def clock_count
          @harness.clock_count
        end

        def reset
          @harness.reset
        end
      end
    end
  end
end
