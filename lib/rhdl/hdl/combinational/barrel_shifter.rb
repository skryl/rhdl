# HDL Combinational Logic Components
# Barrel Shifter - 8-bit fixed width

require_relative '../../dsl/behavior'

module RHDL
  module HDL
    # Barrel Shifter - 8-bit shifter with multiple modes
    # Modes: shift left, shift right (logical/arithmetic), rotate left/right
    class BarrelShifter < Component
      include RHDL::DSL::Behavior

      input :a, width: 8
      input :shift, width: 3
      input :dir      # 0 = left, 1 = right
      input :arith    # 1 = arithmetic right shift (only applies when dir=1, rotate=0)
      input :rotate   # 1 = rotate instead of shift
      output :y, width: 8

      behavior do
        # Pre-compute shifted values for each shift amount
        # Shift left by 0-7
        shl0 = a
        shl1 = a[6..0].concat(lit(0, width: 1))
        shl2 = a[5..0].concat(lit(0, width: 2))
        shl3 = a[4..0].concat(lit(0, width: 3))
        shl4 = a[3..0].concat(lit(0, width: 4))
        shl5 = a[2..0].concat(lit(0, width: 5))
        shl6 = a[1..0].concat(lit(0, width: 6))
        shl7 = a[0].concat(lit(0, width: 7))

        # Shift right logical by 0-7
        shr0 = a
        shr1 = lit(0, width: 1).concat(a[7..1])
        shr2 = lit(0, width: 2).concat(a[7..2])
        shr3 = lit(0, width: 3).concat(a[7..3])
        shr4 = lit(0, width: 4).concat(a[7..4])
        shr5 = lit(0, width: 5).concat(a[7..5])
        shr6 = lit(0, width: 6).concat(a[7..6])
        shr7 = lit(0, width: 7).concat(a[7])

        # Shift right arithmetic by 0-7 (sign extend)
        sign = a[7]
        sar0 = a
        sar1 = sign.concat(a[7..1])
        sar2 = sign.replicate(2).concat(a[7..2])
        sar3 = sign.replicate(3).concat(a[7..3])
        sar4 = sign.replicate(4).concat(a[7..4])
        sar5 = sign.replicate(5).concat(a[7..5])
        sar6 = sign.replicate(6).concat(a[7..6])
        sar7 = sign.replicate(7).concat(a[7])

        # Rotate left by 0-7
        rol0 = a
        rol1 = a[6..0].concat(a[7])
        rol2 = a[5..0].concat(a[7..6])
        rol3 = a[4..0].concat(a[7..5])
        rol4 = a[3..0].concat(a[7..4])
        rol5 = a[2..0].concat(a[7..3])
        rol6 = a[1..0].concat(a[7..2])
        rol7 = a[0].concat(a[7..1])

        # Rotate right by 0-7
        ror0 = a
        ror1 = a[0].concat(a[7..1])
        ror2 = a[1..0].concat(a[7..2])
        ror3 = a[2..0].concat(a[7..3])
        ror4 = a[3..0].concat(a[7..4])
        ror5 = a[4..0].concat(a[7..5])
        ror6 = a[5..0].concat(a[7..6])
        ror7 = a[6..0].concat(a[7])

        # Select based on shift amount for each mode
        shl_result = case_select(shift, {
          0 => shl0, 1 => shl1, 2 => shl2, 3 => shl3,
          4 => shl4, 5 => shl5, 6 => shl6, 7 => shl7
        }, default: shl0)

        shr_result = case_select(shift, {
          0 => shr0, 1 => shr1, 2 => shr2, 3 => shr3,
          4 => shr4, 5 => shr5, 6 => shr6, 7 => shr7
        }, default: shr0)

        sar_result = case_select(shift, {
          0 => sar0, 1 => sar1, 2 => sar2, 3 => sar3,
          4 => sar4, 5 => sar5, 6 => sar6, 7 => sar7
        }, default: sar0)

        rol_result = case_select(shift, {
          0 => rol0, 1 => rol1, 2 => rol2, 3 => rol3,
          4 => rol4, 5 => rol5, 6 => rol6, 7 => rol7
        }, default: rol0)

        ror_result = case_select(shift, {
          0 => ror0, 1 => ror1, 2 => ror2, 3 => ror3,
          4 => ror4, 5 => ror5, 6 => ror6, 7 => ror7
        }, default: ror0)

        # Select based on mode: dir, arith, rotate
        # dir=0: left (rotate ? rol : shl)
        # dir=1: right (rotate ? ror : (arith ? sar : shr))
        left_result = mux(rotate, rol_result, shl_result)
        right_shift = mux(arith, sar_result, shr_result)
        right_result = mux(rotate, ror_result, right_shift)

        y <= mux(dir, right_result, left_result)
      end
    end
  end
end
