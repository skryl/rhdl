# HDL Ripple Carry Adder
# Multi-bit adder (synthesizable)

module RHDL
  module HDL
    class RippleCarryAdder < SimComponent
      parameter :width, default: 8

      input :a, width: :width
      input :b, width: :width
      input :cin
      output :sum, width: :width
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
    end
  end
end
