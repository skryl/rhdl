# HDL Subtractor
# Subtractor using 2's complement

module RHDL
  module HDL
    class Subtractor < SimComponent
      parameter :width, default: 8

      input :a, width: :width
      input :b, width: :width
      input :bin       # Borrow in
      output :diff, width: :width
      output :bout     # Borrow out
      output :overflow

      behavior do
        # Difference: lower 8 bits of a - b - bin
        diff_result = local(:diff_result, a - b - bin, width: 8)
        diff <= diff_result

        # Borrow out: set when a < b + bin (unsigned comparison)
        # Note: parentheses required due to operator precedence (<= and < are same precedence)
        b_plus_bin = local(:b_plus_bin, b + bin, width: 9)
        bout <= (a < b_plus_bin)

        # Overflow for signed arithmetic: when operand signs differ
        # and result sign differs from minuend sign
        a_sign = local(:a_sign, a[7], width: 1)
        b_sign = local(:b_sign, b[7], width: 1)
        diff_sign = local(:diff_sign, diff_result[7], width: 1)
        overflow <= (a_sign ^ b_sign) & (diff_sign ^ a_sign)
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end
    end
  end
end
