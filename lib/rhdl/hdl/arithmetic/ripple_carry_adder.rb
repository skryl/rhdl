# HDL Ripple Carry Adder
# Multi-bit adder (synthesizable)

module RHDL
  module HDL
    class RippleCarryAdder < SimComponent
      input :a, width: 8
      input :b, width: 8
      input :cin
      output :sum, width: 8
      output :cout
      output :overflow

      behavior do
        # Use 9-bit result to capture carry
        result = local(:result, a + b + cin, width: 9)

        # Sum is lower 8 bits
        sum <= result[7..0]

        # Carry out is bit 8
        cout <= result[8]

        # Overflow for signed arithmetic: when signs of operands match
        # but sign of result differs
        a_sign = local(:a_sign, a[7], width: 1)
        b_sign = local(:b_sign, b[7], width: 1)
        sum_sign = local(:sum_sign, result[7], width: 1)
        overflow <= (a_sign ^ sum_sign) & ~(a_sign ^ b_sign)
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

      # Behavior block handles both simulation and synthesis
    end
  end
end
