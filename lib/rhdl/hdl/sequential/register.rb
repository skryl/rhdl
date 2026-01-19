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

      parameter :width, default: 8

      input :d, width: :width
      input :clk
      input :rst, default: 0
      input :en, default: 0
      output :q, width: :width

      # Sequential block for register
      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        q <= mux(en, d, q)
      end
    end
  end
end
