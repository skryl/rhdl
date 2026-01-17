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

module RHDL
  module HDL
    class ALU < SimComponent
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

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :b, width: @width
        input :op, width: 4
        input :cin
        output :result, width: @width
        output :cout
        output :zero
        output :negative
        output :overflow
      end

      def propagate
        a = in_val(:a)
        b = in_val(:b)
        op = in_val(:op)
        cin = in_val(:cin) & 1
        mask = (1 << @width) - 1

        result = 0
        cout = 0
        overflow = 0

        case op
        when OP_ADD
          full = a + b + cin
          result = full & mask
          cout = (full >> @width) & 1
          # Signed overflow
          a_sign = (a >> (@width - 1)) & 1
          b_sign = (b >> (@width - 1)) & 1
          r_sign = (result >> (@width - 1)) & 1
          overflow = ((a_sign == b_sign) && (r_sign != a_sign)) ? 1 : 0

        when OP_SUB
          full = a - b - cin
          result = full & mask
          cout = (a < (b + cin)) ? 1 : 0  # Borrow
          a_sign = (a >> (@width - 1)) & 1
          b_sign = (b >> (@width - 1)) & 1
          r_sign = (result >> (@width - 1)) & 1
          overflow = ((a_sign != b_sign) && (r_sign != a_sign)) ? 1 : 0

        when OP_AND
          result = a & b

        when OP_OR
          result = a | b

        when OP_XOR
          result = a ^ b

        when OP_NOT
          result = (~a) & mask

        when OP_SHL
          shift_amt = b & 0x07  # Limit shift to 0-7
          full = a << shift_amt
          result = full & mask
          cout = (full >> @width) & 1

        when OP_SHR
          shift_amt = b & 0x07
          result = a >> shift_amt
          cout = shift_amt > 0 ? ((a >> (shift_amt - 1)) & 1) : 0

        when OP_SAR  # Arithmetic right shift (sign extend)
          shift_amt = b & 0x07
          sign = (a >> (@width - 1)) & 1
          result = a >> shift_amt
          if sign == 1
            # Fill in high bits with 1s
            result |= (mask << (@width - shift_amt)) & mask
          end
          cout = shift_amt > 0 ? ((a >> (shift_amt - 1)) & 1) : 0

        when OP_ROL  # Rotate left
          shift_amt = b & 0x07
          result = ((a << shift_amt) | (a >> (@width - shift_amt))) & mask
          cout = (a >> (@width - 1)) & 1

        when OP_ROR  # Rotate right
          shift_amt = b & 0x07
          result = ((a >> shift_amt) | (a << (@width - shift_amt))) & mask
          cout = a & 1

        when OP_MUL
          product = a * b
          result = product & mask  # Low byte
          cout = ((product >> @width) != 0) ? 1 : 0  # High byte non-zero

        when OP_DIV
          if b == 0
            result = 0     # Return 0 for divide by zero (matches behavioral CPU)
            cout = 1       # Error flag
          else
            result = a / b
          end

        when OP_MOD
          if b == 0
            result = a  # Return original on divide by zero
            cout = 1
          else
            result = a % b
          end

        when OP_INC
          result = (a + 1) & mask
          cout = (a == mask) ? 1 : 0
          overflow = (a == (mask >> 1)) ? 1 : 0  # 0x7F -> 0x80 for signed

        when OP_DEC
          result = (a - 1) & mask
          cout = (a == 0) ? 1 : 0
          overflow = (a == (1 << (@width - 1))) ? 1 : 0  # 0x80 -> 0x7F for signed
        end

        zero = (result == 0) ? 1 : 0
        negative = (result >> (@width - 1)) & 1

        out_set(:result, result)
        out_set(:cout, cout)
        out_set(:zero, zero)
        out_set(:negative, negative)
        out_set(:overflow, overflow)
      end
    end
  end
end
