# HDL Shift Register
# Shift Register with serial/parallel I/O
# Synthesizable via Sequential DSL

require_relative '../../dsl/behavior'
require_relative '../../dsl/sequential'

module RHDL
  module HDL
    class ShiftRegister < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      port_input :d_in       # Serial input
      port_input :clk
      port_input :rst
      port_input :en
      port_input :dir        # 0 = right, 1 = left
      port_input :load       # Parallel load enable
      port_input :d, width: 8  # Parallel load data
      port_output :q, width: 8
      port_output :d_out     # Serial output

      # Sequential block for shift register
      # Priority: load > en (shift)
      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        # Shift right: d_in becomes MSB, shift others down
        shift_right = cat(d_in, q[7..1])
        # Shift left: d_in becomes LSB, shift others up
        shift_left = cat(q[6..0], d_in)
        # Select direction
        shift_result = mux(dir, shift_left, shift_right)
        # Priority: load > shift
        q <= mux(load, d, mux(en, shift_result, q))
      end

      # Combinational output for serial data
      behavior do
        # Serial out: LSB when right, MSB when left
        d_out <= mux(dir, q[7], q[0])
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
