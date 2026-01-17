# HDL Subtractor
# Subtractor using 2's complement

module RHDL
  module HDL
    class Subtractor < SimComponent
      # Class-level port definitions for synthesis (default 8-bit width)
      port_input :a, width: 8
      port_input :b, width: 8
      port_input :bin       # Borrow in
      port_output :diff, width: 8
      port_output :bout     # Borrow out
      port_output :overflow

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

      def setup_ports
        # Override default width if different from 8
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:b] = Wire.new("#{@name}.b", width: @width)
        @outputs[:diff] = Wire.new("#{@name}.diff", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end
    end
  end
end
