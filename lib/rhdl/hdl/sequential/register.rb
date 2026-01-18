# HDL Register
# Multi-bit Register with synchronous reset and enable
# Synthesizable via Sequential DSL

require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    class Register < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :d, width: 8
      input :clk
      input :rst
      input :en
      output :q, width: 8

      # Sequential block for register
      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        q <= mux(en, d, q)
      end
    end
  end
end
