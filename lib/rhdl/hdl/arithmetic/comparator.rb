# HDL Comparator
# Compares two values

module RHDL
  module HDL
    class Comparator < SimComponent
      # Class-level port definitions for synthesis (default 8-bit width)
      input :a, width: 8
      input :b, width: 8
      input :signed_cmp   # 1 = signed comparison (renamed to avoid keyword conflict)
      output :eq      # a == b
      output :gt      # a > b
      output :lt      # a < b
      output :gte     # a >= b
      output :lte     # a <= b

      behavior do
        # Unsigned comparisons
        unsigned_eq = local(:unsigned_eq, a == b, width: 1)
        unsigned_gt = local(:unsigned_gt, a > b, width: 1)
        unsigned_lt = local(:unsigned_lt, a < b, width: 1)

        # Sign bits
        a_sign = local(:a_sign, a[7], width: 1)
        b_sign = local(:b_sign, b[7], width: 1)

        # Signed comparisons:
        # If signs differ: negative < positive
        # If signs same: compare as unsigned
        signs_differ = local(:signs_differ, a_sign ^ b_sign, width: 1)

        # When signs differ: a<b if a is negative (a_sign=1)
        # When signs same: use unsigned comparison
        signed_lt = local(:signed_lt, mux(signs_differ, a_sign, unsigned_lt), width: 1)
        signed_gt = local(:signed_gt, mux(signs_differ, b_sign, unsigned_gt), width: 1)
        signed_eq = local(:signed_eq, unsigned_eq, width: 1)  # Equality is the same

        # Select based on signed_cmp flag
        eq <= mux(signed_cmp, signed_eq, unsigned_eq)
        gt <= mux(signed_cmp, signed_gt, unsigned_gt)
        lt <= mux(signed_cmp, signed_lt, unsigned_lt)

        # Derived outputs
        eq_result = local(:eq_result, mux(signed_cmp, signed_eq, unsigned_eq), width: 1)
        gt_result = local(:gt_result, mux(signed_cmp, signed_gt, unsigned_gt), width: 1)
        lt_result = local(:lt_result, mux(signed_cmp, signed_lt, unsigned_lt), width: 1)
        gte <= eq_result | gt_result
        lte <= eq_result | lt_result
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
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end
    end
  end
end
