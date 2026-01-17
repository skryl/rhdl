# HDL Counter
# Binary Counter with up/down, load, and wrap
# Synthesizable via Sequential DSL

require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    class Counter < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      port_input :clk
      port_input :rst
      port_input :en
      port_input :up        # 1 = count up, 0 = count down
      port_input :load
      port_input :d, width: 8
      port_output :q, width: 8
      port_output :tc       # Terminal count (max when up, 0 when down)
      port_output :zero     # Zero flag

      # Sequential block for counter
      # Priority: load > en (count)
      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        # Count up or down
        count_up = q + lit(1, width: 8)
        count_down = q - lit(1, width: 8)
        count_result = mux(up, count_up, count_down)
        # load > count
        q <= mux(load, d, mux(en, count_result, q))
      end

      # Combinational outputs
      behavior do
        # Terminal count: max (0xFF) when up, 0 when down
        is_max = (q == lit(0xFF, width: 8))
        is_zero = (q == lit(0, width: 8))
        tc <= mux(up, is_max, is_zero)
        zero <= is_zero
      end
    end
  end
end
