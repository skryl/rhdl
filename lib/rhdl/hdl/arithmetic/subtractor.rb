# HDL Subtractor
# Subtractor using 2's complement

module RHDL
  module HDL
    class Subtractor < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :b, width: @width
        input :bin       # Borrow in
        output :diff, width: @width
        output :bout     # Borrow out
        output :overflow
      end

      def propagate
        a = in_val(:a)
        b = in_val(:b)
        bin = in_val(:bin) & 1
        mask = (1 << @width) - 1

        # a - b - bin using 2's complement
        diff = (a - b - bin) & mask
        bout = (a < (b + bin)) ? 1 : 0

        # Overflow for signed arithmetic
        a_sign = (a >> (@width - 1)) & 1
        b_sign = (b >> (@width - 1)) & 1
        diff_sign = (diff >> (@width - 1)) & 1
        overflow = ((a_sign != b_sign) && (diff_sign != a_sign)) ? 1 : 0

        out_set(:diff, diff)
        out_set(:bout, bout)
        out_set(:overflow, overflow)
      end
    end
  end
end
