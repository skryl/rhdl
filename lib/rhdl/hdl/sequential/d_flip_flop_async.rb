# HDL D Flip-Flop with Async Reset
# D Flip-Flop with asynchronous reset
# Synthesizable via Sequential DSL
# Note: Currently generates synchronous reset in Verilog; async reset support requires DSL extension

require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    class DFlipFlopAsync < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :d
      input :clk
      input :rst
      input :en
      output :q
      output :qn

      # Sequential block for flip-flop
      # Note: Async reset behavior is simulated, but synthesized as sync reset
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
