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

      port_input :d, width: 8
      port_input :clk
      port_input :rst
      port_input :load
      port_output :q, width: 8

      # Sequential block for register with load
      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        q <= mux(load, d, q)
      end
    end
  end
end
