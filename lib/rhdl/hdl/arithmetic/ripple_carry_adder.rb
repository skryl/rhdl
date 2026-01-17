# HDL Ripple Carry Adder
# Multi-bit adder

module RHDL
  module HDL
    class RippleCarryAdder < SimComponent
      port_input :a, width: 8
      port_input :b, width: 8
      port_input :cin
      port_output :sum, width: 8
      port_output :cout
      port_output :overflow

      # Behavior block defines synthesizable logic for sum
      # cout and overflow require wider temporary or more complex expressions
      behavior do
        sum <= a + b + cin
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        # Override default width if different from 8-bit
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:b] = Wire.new("#{@name}.b", width: @width)
        @outputs[:sum] = Wire.new("#{@name}.sum", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end

      # Manual propagate computes cout and overflow which require wider arithmetic
      def propagate
        a = in_val(:a)
        b = in_val(:b)
        cin = in_val(:cin) & 1

        result = a + b + cin
        mask = (1 << @width) - 1
        sum = result & mask
        cout = (result >> @width) & 1

        # Overflow for signed arithmetic
        a_sign = (a >> (@width - 1)) & 1
        b_sign = (b >> (@width - 1)) & 1
        sum_sign = (sum >> (@width - 1)) & 1
        overflow = ((a_sign == b_sign) && (sum_sign != a_sign)) ? 1 : 0

        out_set(:sum, sum)
        out_set(:cout, cout)
        out_set(:overflow, overflow)
      end
    end
  end
end
