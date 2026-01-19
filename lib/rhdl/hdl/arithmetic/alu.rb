# HDL ALU
# Full ALU with multiple operations
# Op codes:
#   0000 = ADD
#   0001 = SUB
#   0010 = AND
#   0011 = OR
#   0100 = XOR
#   0101 = NOT A
#   0110 = SHL (shift left)
#   0111 = SHR (shift right logical)
#   1000 = SAR (shift right arithmetic)
#   1001 = ROL (rotate left)
#   1010 = ROR (rotate right)
#   1011 = MUL (low byte of product)
#   1100 = DIV (quotient)
#   1101 = MOD (remainder)
#   1110 = INC (increment A)
#   1111 = DEC (decrement A)

require_relative '../../dsl/behavior'

module RHDL
  module HDL
    class ALU < SimComponent
      include RHDL::DSL::Behavior

      # Operation constants
      OP_ADD = 0
      OP_SUB = 1
      OP_AND = 2
      OP_OR  = 3
      OP_XOR = 4
      OP_NOT = 5
      OP_SHL = 6
      OP_SHR = 7
      OP_SAR = 8
      OP_ROL = 9
      OP_ROR = 10
      OP_MUL = 11
      OP_DIV = 12
      OP_MOD = 13
      OP_INC = 14
      OP_DEC = 15

      parameter :width, default: 8

      input :a, width: :width
      input :b, width: :width
      input :op, width: 4
      input :cin, default: 0
      output :result, width: :width
      output :cout
      output :zero
      output :negative
      output :overflow

      behavior do
        # Addition: a + b + cin (9 bits to capture carry)
        add_full = a + b + cin
        add_result = add_full[7..0]
        add_cout = add_full[8]
        # Overflow: same signs in, different sign out
        add_overflow = ((a[7] == b[7]) & (add_result[7] != a[7]))

        # Subtraction: a - b - cin
        sub_full = a - b - cin
        sub_result = sub_full[7..0]
        sub_cout = mux(a < (b + cin), lit(1, width: 1), lit(0, width: 1))
        # Overflow: different signs in, result sign != a sign
        sub_overflow = ((a[7] != b[7]) & (sub_result[7] != a[7]))

        # Bitwise operations
        and_result = a & b
        or_result = a | b
        xor_result = a ^ b
        not_result = ~a

        # Shift operations - use barrel-shifter style for each shift amount
        shift_amt = b[2..0]

        # Shift left by 0-7
        shl0 = a
        shl1 = a[6..0].concat(lit(0, width: 1))
        shl2 = a[5..0].concat(lit(0, width: 2))
        shl3 = a[4..0].concat(lit(0, width: 3))
        shl4 = a[3..0].concat(lit(0, width: 4))
        shl5 = a[2..0].concat(lit(0, width: 5))
        shl6 = a[1..0].concat(lit(0, width: 6))
        shl7 = a[0].concat(lit(0, width: 7))

        shl_result = case_select(shift_amt, {
          0 => shl0, 1 => shl1, 2 => shl2, 3 => shl3,
          4 => shl4, 5 => shl5, 6 => shl6, 7 => shl7
        }, default: shl0)

        # Shift right logical by 0-7
        shr0 = a
        shr1 = lit(0, width: 1).concat(a[7..1])
        shr2 = lit(0, width: 2).concat(a[7..2])
        shr3 = lit(0, width: 3).concat(a[7..3])
        shr4 = lit(0, width: 4).concat(a[7..4])
        shr5 = lit(0, width: 5).concat(a[7..5])
        shr6 = lit(0, width: 6).concat(a[7..6])
        shr7 = lit(0, width: 7).concat(a[7])

        shr_result = case_select(shift_amt, {
          0 => shr0, 1 => shr1, 2 => shr2, 3 => shr3,
          4 => shr4, 5 => shr5, 6 => shr6, 7 => shr7
        }, default: shr0)

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

        sar_result = case_select(shift_amt, {
          0 => sar0, 1 => sar1, 2 => sar2, 3 => sar3,
          4 => sar4, 5 => sar5, 6 => sar6, 7 => sar7
        }, default: sar0)

        # Rotate left by 0-7
        rol0 = a
        rol1 = a[6..0].concat(a[7])
        rol2 = a[5..0].concat(a[7..6])
        rol3 = a[4..0].concat(a[7..5])
        rol4 = a[3..0].concat(a[7..4])
        rol5 = a[2..0].concat(a[7..3])
        rol6 = a[1..0].concat(a[7..2])
        rol7 = a[0].concat(a[7..1])

        rol_result = case_select(shift_amt, {
          0 => rol0, 1 => rol1, 2 => rol2, 3 => rol3,
          4 => rol4, 5 => rol5, 6 => rol6, 7 => rol7
        }, default: rol0)

        # Rotate right by 0-7
        ror0 = a
        ror1 = a[0].concat(a[7..1])
        ror2 = a[1..0].concat(a[7..2])
        ror3 = a[2..0].concat(a[7..3])
        ror4 = a[3..0].concat(a[7..4])
        ror5 = a[4..0].concat(a[7..5])
        ror6 = a[5..0].concat(a[7..6])
        ror7 = a[6..0].concat(a[7])

        ror_result = case_select(shift_amt, {
          0 => ror0, 1 => ror1, 2 => ror2, 3 => ror3,
          4 => ror4, 5 => ror5, 6 => ror6, 7 => ror7
        }, default: ror0)

        # Multiply: a * b (full 16 bits, we take low 8)
        mul_full = a * b
        mul_result = mul_full[7..0]
        mul_cout = mux(mul_full[15..8] != lit(0, width: 8), lit(1, width: 1), lit(0, width: 1))

        # Division and modulo
        div_result = a / b
        mod_result = a % b
        # Division by zero sets cout
        div_cout = mux(b == lit(0, width: 8), lit(1, width: 1), lit(0, width: 1))

        # Increment and decrement
        inc_full = a + lit(1, width: 8)
        inc_result = inc_full[7..0]
        inc_cout = inc_full[8]
        inc_overflow = mux(a == lit(127, width: 8), lit(1, width: 1), lit(0, width: 1))

        dec_result = (a - lit(1, width: 8))[7..0]
        dec_cout = mux(a == lit(0, width: 8), lit(1, width: 1), lit(0, width: 1))
        dec_overflow = mux(a == lit(128, width: 8), lit(1, width: 1), lit(0, width: 1))

        # Select result based on opcode
        result <= case_select(op, {
          OP_ADD => add_result,
          OP_SUB => sub_result,
          OP_AND => and_result,
          OP_OR  => or_result,
          OP_XOR => xor_result,
          OP_NOT => not_result,
          OP_SHL => shl_result,
          OP_SHR => shr_result,
          OP_SAR => sar_result,
          OP_ROL => rol_result,
          OP_ROR => ror_result,
          OP_MUL => mul_result,
          OP_DIV => div_result,
          OP_MOD => mod_result,
          OP_INC => inc_result,
          OP_DEC => dec_result
        }, default: add_result)

        # Select cout based on opcode
        cout <= case_select(op, {
          OP_ADD => add_cout,
          OP_SUB => sub_cout,
          OP_AND => lit(0, width: 1),
          OP_OR  => lit(0, width: 1),
          OP_XOR => lit(0, width: 1),
          OP_NOT => lit(0, width: 1),
          OP_SHL => a[7],  # MSB shifted out
          OP_SHR => a[0],  # LSB shifted out
          OP_SAR => a[0],
          OP_ROL => a[7],
          OP_ROR => a[0],
          OP_MUL => mul_cout,
          OP_DIV => div_cout,
          OP_MOD => div_cout,
          OP_INC => inc_cout,
          OP_DEC => dec_cout
        }, default: add_cout)

        # Select overflow based on opcode
        overflow <= case_select(op, {
          OP_ADD => add_overflow,
          OP_SUB => sub_overflow,
          OP_AND => lit(0, width: 1),
          OP_OR  => lit(0, width: 1),
          OP_XOR => lit(0, width: 1),
          OP_NOT => lit(0, width: 1),
          OP_SHL => lit(0, width: 1),
          OP_SHR => lit(0, width: 1),
          OP_SAR => lit(0, width: 1),
          OP_ROL => lit(0, width: 1),
          OP_ROR => lit(0, width: 1),
          OP_MUL => lit(0, width: 1),
          OP_DIV => lit(0, width: 1),
          OP_MOD => lit(0, width: 1),
          OP_INC => inc_overflow,
          OP_DEC => dec_overflow
        }, default: add_overflow)

        # Zero and negative flags depend on result
        # We need to compute which result is active
        active_result = case_select(op, {
          OP_ADD => add_result,
          OP_SUB => sub_result,
          OP_AND => and_result,
          OP_OR  => or_result,
          OP_XOR => xor_result,
          OP_NOT => not_result,
          OP_SHL => shl_result,
          OP_SHR => shr_result,
          OP_SAR => sar_result,
          OP_ROL => rol_result,
          OP_ROR => ror_result,
          OP_MUL => mul_result,
          OP_DIV => div_result,
          OP_MOD => mod_result,
          OP_INC => inc_result,
          OP_DEC => dec_result
        }, default: add_result)

        zero <= mux(active_result == lit(0, width: 8), lit(1, width: 1), lit(0, width: 1))
        negative <= active_result[7]
      end
    end
  end
end
