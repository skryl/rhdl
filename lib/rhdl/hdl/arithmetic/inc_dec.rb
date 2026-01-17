# HDL Increment/Decrement Unit
# Increment or decrement by 1

module RHDL
  module HDL
    class IncDec < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :inc    # 1 = increment, 0 = decrement
        output :result, width: @width
        output :cout  # Carry/borrow
      end

      def propagate
        a = in_val(:a)
        mask = (1 << @width) - 1

        if in_val(:inc) == 1
          result = (a + 1) & mask
          cout = (a == mask) ? 1 : 0  # Overflow to 0
        else
          result = (a - 1) & mask
          cout = (a == 0) ? 1 : 0     # Underflow from 0
        end

        out_set(:result, result)
        out_set(:cout, cout)
      end
    end
  end
end
