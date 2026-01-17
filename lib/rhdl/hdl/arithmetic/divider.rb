# HDL Divider
# Combinational divider

module RHDL
  module HDL
    class Divider < SimComponent
      # Class-level port definitions for synthesis (default 8-bit width)
      port_input :dividend, width: 8
      port_input :divisor, width: 8
      port_output :quotient, width: 8
      port_output :remainder, width: 8
      port_output :div_by_zero

      behavior do
        # Check for division by zero
        is_zero = local(:is_zero, divisor == lit(0, width: 8), width: 1)
        div_by_zero <= is_zero

        # Compute quotient and remainder (when divisor != 0)
        normal_quotient = local(:normal_quotient, dividend / divisor, width: 8)
        normal_remainder = local(:normal_remainder, dividend % divisor, width: 8)

        # Select between normal result and error result
        # When div_by_zero: quotient=0, remainder=0
        # When not div_by_zero: use computed values
        quotient <= mux(is_zero, lit(0, width: 8), normal_quotient)
        remainder <= mux(is_zero, lit(0, width: 8), normal_remainder)
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        # Override default width if different from 8
        return if @width == 8
        @inputs[:dividend] = Wire.new("#{@name}.dividend", width: @width)
        @inputs[:divisor] = Wire.new("#{@name}.divisor", width: @width)
        @outputs[:quotient] = Wire.new("#{@name}.quotient", width: @width)
        @outputs[:remainder] = Wire.new("#{@name}.remainder", width: @width)
        @inputs[:dividend].on_change { |_| propagate }
        @inputs[:divisor].on_change { |_| propagate }
      end
    end
  end
end
