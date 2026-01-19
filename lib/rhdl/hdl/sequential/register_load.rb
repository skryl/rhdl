# HDL Register with Load
# Register with load capability
# Synthesizable via Sequential DSL

require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    class RegisterLoad < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :d, width: 8
      input :clk
      input :rst
      input :load
      output :q, width: 8

      # Sequential block for register with load
      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        q <= mux(load, d, q)
      end
    end
  end
end
