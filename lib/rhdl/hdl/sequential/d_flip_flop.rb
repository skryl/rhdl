# HDL D Flip-Flop
# D Flip-Flop with synchronous reset and enable
# Synthesizable via Sequential DSL

require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    class DFlipFlop < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      port_input :d
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q
      port_output :qn

      # Sequential block for the flip-flop register
      # Priority: rst > ~en (hold) > d
      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        q <= mux(en, d, q)
      end

      # Combinational block for inverted output
      behavior do
        qn <= ~q
      end
    end
  end
end
