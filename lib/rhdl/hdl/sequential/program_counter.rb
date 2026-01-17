# HDL Program Counter
# 16-bit Program Counter for CPU
# Synthesizable via Sequential DSL

require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    class ProgramCounter < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      port_input :clk
      port_input :rst
      port_input :en          # Increment enable
      port_input :load        # Load new address
      port_input :d, width: 16
      port_input :inc, width: 16  # Increment amount (usually 1, 2, or 3)
      port_output :q, width: 16

      # Sequential block for program counter
      # Priority: load > en (increment)
      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        # Default increment of 1 when inc is 0
        inc_is_zero = (inc == lit(0, width: 16))
        inc_val = mux(inc_is_zero, lit(1, width: 16), inc)
        next_pc = q + inc_val
        # Priority: load > increment
        q <= mux(load, d, mux(en, next_pc, q))
      end
    end
  end
end
