# HDL JK Flip-Flop
# JK Flip-Flop with all standard operations
# Synthesizable via Sequential DSL

require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    class JKFlipFlop < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      port_input :j
      port_input :k
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q
      port_output :qn

      # Sequential block for JK flip-flop
      # JK truth table: J=0,K=0 -> hold; J=0,K=1 -> reset; J=1,K=0 -> set; J=1,K=1 -> toggle
      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        # JK logic with enable
        # j=1: k=1 -> toggle, k=0 -> set(1)
        # j=0: k=1 -> reset(0), k=0 -> hold
        jk_result = mux(j,
          mux(k, ~q, lit(1, width: 1)),     # j=1: k ? toggle : set
          mux(k, lit(0, width: 1), q))      # j=0: k ? reset : hold
        q <= mux(en, jk_result, q)
      end

      # Combinational block for inverted output
      behavior do
        qn <= ~q
      end
    end
  end
end
