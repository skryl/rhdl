# HDL Add-Subtract Unit
# Combined adder/subtractor

module RHDL
  module HDL
    class AddSub < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :b, width: @width
        input :sub      # 0 = add, 1 = subtract
        output :result, width: @width
        output :cout
        output :overflow
        output :zero
        output :negative
      end

      def propagate
        a = in_val(:a)
        b = in_val(:b)
        sub = in_val(:sub) & 1
        mask = (1 << @width) - 1

        if sub == 0
          result = a + b
        else
          result = a - b
        end

        final = result & mask
        cout = sub == 0 ? ((result >> @width) & 1) : (a < b ? 1 : 0)

        # Flags
        a_sign = (a >> (@width - 1)) & 1
        b_sign = (b >> (@width - 1)) & 1
        r_sign = (final >> (@width - 1)) & 1

        if sub == 0
          overflow = ((a_sign == b_sign) && (r_sign != a_sign)) ? 1 : 0
        else
          overflow = ((a_sign != b_sign) && (r_sign != a_sign)) ? 1 : 0
        end

        out_set(:result, final)
        out_set(:cout, cout)
        out_set(:overflow, overflow)
        out_set(:zero, final == 0 ? 1 : 0)
        out_set(:negative, r_sign)
      end
    end
  end
end
