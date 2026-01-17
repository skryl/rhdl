# HDL SR Flip-Flop
# Set-Reset Flip-Flop
# Synthesizable via Sequential DSL

require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    class SRFlipFlop < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      port_input :s
      port_input :r
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q
      port_output :qn

      # Sequential block for SR flip-flop
      # SR truth table: S=1,R=0 -> set; S=0,R=1 -> reset; S=R=0 -> hold; S=R=1 -> invalid (R takes precedence)
      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        # R has priority: r=1 -> reset(0), else s ? set(1) : hold(q)
        sr_result = mux(r, lit(0, width: 1), mux(s, lit(1, width: 1), q))
        q <= mux(en, sr_result, q)
      end

      # Combinational block for inverted output
      behavior do
        qn <= ~q
      end
    end
  end
end
