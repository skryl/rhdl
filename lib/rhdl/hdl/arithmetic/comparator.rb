# HDL Comparator
# Compares two values

module RHDL
  module HDL
    class Comparator < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :b, width: @width
        input :signed   # 1 = signed comparison
        output :eq      # a == b
        output :gt      # a > b
        output :lt      # a < b
        output :gte     # a >= b
        output :lte     # a <= b
      end

      def propagate
        a = in_val(:a)
        b = in_val(:b)
        signed = in_val(:signed) & 1

        if signed == 1
          # Convert to signed
          sign_bit = 1 << (@width - 1)
          a_signed = a >= sign_bit ? a - (1 << @width) : a
          b_signed = b >= sign_bit ? b - (1 << @width) : b
          eq = a_signed == b_signed ? 1 : 0
          gt = a_signed > b_signed ? 1 : 0
          lt = a_signed < b_signed ? 1 : 0
        else
          eq = a == b ? 1 : 0
          gt = a > b ? 1 : 0
          lt = a < b ? 1 : 0
        end

        out_set(:eq, eq)
        out_set(:gt, gt)
        out_set(:lt, lt)
        out_set(:gte, (eq == 1 || gt == 1) ? 1 : 0)
        out_set(:lte, (eq == 1 || lt == 1) ? 1 : 0)
      end
    end
  end
end
