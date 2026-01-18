# HDL Divider
# Combinational divider

module RHDL
  module HDL
    class Divider < SimComponent
      parameter :width, default: 8

      input :dividend, width: :width
      input :divisor, width: :width
      output :quotient, width: :width
      output :remainder, width: :width
      output :div_by_zero

      behavior do
        w = port_width(:dividend)
        # Check for division by zero
        is_zero = local(:is_zero, divisor == lit(0, width: w), width: 1)
        div_by_zero <= is_zero

        # Compute quotient and remainder (when divisor != 0)
        normal_quotient = local(:normal_quotient, dividend / divisor, width: w)
        normal_remainder = local(:normal_remainder, dividend % divisor, width: w)

        # Select between normal result and error result
        # When div_by_zero: quotient=0, remainder=0
        # When not div_by_zero: use computed values
        quotient <= mux(is_zero, lit(0, width: w), normal_quotient)
        remainder <= mux(is_zero, lit(0, width: w), normal_remainder)
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end
    end
  end
end
