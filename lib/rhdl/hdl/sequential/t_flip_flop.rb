# HDL T Flip-Flop
# Toggle Flip-Flop
# Synthesizable via Sequential DSL

require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    class TFlipFlop < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :t
      input :clk
      input :rst
      input :en
      output :q
      output :qn

      # Sequential block for toggle flip-flop
      # Toggle when t=1 and en=1, otherwise hold
      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        # Toggle when t & en, otherwise hold
        q <= mux(t & en, ~q, q)
      end

      # Combinational block for inverted output
      behavior do
        qn <= ~q
      end
    end
  end
end
