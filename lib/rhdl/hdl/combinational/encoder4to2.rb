# HDL Combinational Logic Components
# 4-to-2 Priority Encoder

module RHDL
  module HDL
    # 4-to-2 Priority Encoder - encodes highest set bit position
    class Encoder4to2 < SimComponent
      port_input :a, width: 4
      port_output :y, width: 2
      port_output :valid

      behavior do
        # Priority encoder: find highest set bit
        # Check bits from high to low: a[3], a[2], a[1], a[0]
        is_3 = local(:is_3, a[3], width: 1)
        is_2 = local(:is_2, ~a[3] & a[2], width: 1)
        is_1 = local(:is_1, ~a[3] & ~a[2] & a[1], width: 1)
        is_0 = local(:is_0, ~a[3] & ~a[2] & ~a[1] & a[0], width: 1)

        # Output encoded value: 3 if a[3], 2 if a[2], 1 if a[1], 0 if a[0]
        y <= cat(is_3 | is_2, is_3 | is_1)
        valid <= a[3] | a[2] | a[1] | a[0]
      end

      def propagate
        val = in_val(:a) & 0xF
        if val == 0
          out_set(:y, 0)
          out_set(:valid, 0)
        elsif (val & 8) != 0
          out_set(:y, 3)
          out_set(:valid, 1)
        elsif (val & 4) != 0
          out_set(:y, 2)
          out_set(:valid, 1)
        elsif (val & 2) != 0
          out_set(:y, 1)
          out_set(:valid, 1)
        else
          out_set(:y, 0)
          out_set(:valid, 1)
        end
      end
    end
  end
end
