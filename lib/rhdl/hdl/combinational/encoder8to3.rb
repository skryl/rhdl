# HDL Combinational Logic Components
# 8-to-3 Priority Encoder

module RHDL
  module HDL
    # 8-to-3 Priority Encoder - encodes highest set bit position
    class Encoder8to3 < SimComponent
      port_input :a, width: 8
      port_output :y, width: 3
      port_output :valid

      behavior do
        # Priority encoder: find highest set bit (7 down to 0)
        # Bit masks for each position
        is_7 = local(:is_7, a[7], width: 1)
        is_6 = local(:is_6, ~a[7] & a[6], width: 1)
        is_5 = local(:is_5, ~a[7] & ~a[6] & a[5], width: 1)
        is_4 = local(:is_4, ~a[7] & ~a[6] & ~a[5] & a[4], width: 1)
        is_3 = local(:is_3, ~a[7] & ~a[6] & ~a[5] & ~a[4] & a[3], width: 1)
        is_2 = local(:is_2, ~a[7] & ~a[6] & ~a[5] & ~a[4] & ~a[3] & a[2], width: 1)
        is_1 = local(:is_1, ~a[7] & ~a[6] & ~a[5] & ~a[4] & ~a[3] & ~a[2] & a[1], width: 1)
        is_0 = local(:is_0, ~a[7] & ~a[6] & ~a[5] & ~a[4] & ~a[3] & ~a[2] & ~a[1] & a[0], width: 1)

        # Output encoded value: bit 2 = (4,5,6,7), bit 1 = (2,3,6,7), bit 0 = (1,3,5,7)
        y2 = local(:y2, is_4 | is_5 | is_6 | is_7, width: 1)
        y1 = local(:y1, is_2 | is_3 | is_6 | is_7, width: 1)
        y0 = local(:y0, is_1 | is_3 | is_5 | is_7, width: 1)
        y <= cat(y2, y1, y0)
        valid <= a[7] | a[6] | a[5] | a[4] | a[3] | a[2] | a[1] | a[0]
      end

    end
  end
end
