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

      port_input :d, width: 8
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q, width: 8

      # Sequential block for register
      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        q <= mux(en, d, q)
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:d] = Wire.new("#{@name}.d", width: @width)
        @outputs[:q] = Wire.new("#{@name}.q", width: @width)
      end
    end
  end
end
