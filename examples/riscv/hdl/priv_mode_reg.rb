# Privilege mode register
# Tracks current privilege level across trap entry and mret/sret returns.

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'
require_relative 'constants'

module RHDL
  module Examples
    module RISCV
      class PrivModeReg < RHDL::HDL::SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        input :clk
        input :rst
        input :mode_next, width: 2
        input :mode_we

        output :mode, width: 2

        sequential clock: :clk, reset: :rst, reset_values: { mode: PrivMode::MACHINE } do
          mode <= mux(mode_we, mode_next, mode)
        end
      end
    end
  end
end
