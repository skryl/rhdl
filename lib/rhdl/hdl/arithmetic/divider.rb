# HDL Divider
# Combinational divider

module RHDL
  module HDL
    class Divider < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :dividend, width: @width
        input :divisor, width: @width
        output :quotient, width: @width
        output :remainder, width: @width
        output :div_by_zero
      end

      def propagate
        dividend = in_val(:dividend)
        divisor = in_val(:divisor)

        if divisor == 0
          out_set(:quotient, 0)
          out_set(:remainder, 0)
          out_set(:div_by_zero, 1)
        else
          out_set(:quotient, dividend / divisor)
          out_set(:remainder, dividend % divisor)
          out_set(:div_by_zero, 0)
        end
      end
    end
  end
end
