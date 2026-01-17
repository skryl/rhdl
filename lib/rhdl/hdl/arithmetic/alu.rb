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

      # Class-level port definitions for synthesis (default 8-bit width)
      port_input :a, width: 8
      port_input :b, width: 8
      port_input :op, width: 4
      port_input :cin
      port_output :result, width: 8
      port_output :cout
      port_output :zero
      port_output :negative
      port_output :overflow

      # Note: Behavior block for synthesis only - uses case_select for operation dispatch
      # The simulation uses the manual propagate method below due to complexity
      behavior do
        # Compute results for each operation
        add_result = local(:add_result, a + b + cin, width: 8)
        sub_result = local(:sub_result, a - b - cin, width: 8)
        and_result = local(:and_result, a & b, width: 8)
        or_result = local(:or_result, a | b, width: 8)
        xor_result = local(:xor_result, a ^ b, width: 8)
        not_result = local(:not_result, ~a, width: 8)
        shl_result = local(:shl_result, a << (b & lit(7, width: 3)), width: 8)
        shr_result = local(:shr_result, a >> (b & lit(7, width: 3)), width: 8)
        mul_result = local(:mul_result, a * b, width: 8)
        div_result = local(:div_result, mux(b == lit(0, width: 8), lit(0, width: 8), a / b), width: 8)
        mod_result = local(:mod_result, mux(b == lit(0, width: 8), a, a % b), width: 8)
        inc_result = local(:inc_result, a + lit(1, width: 8), width: 8)
        dec_result = local(:dec_result, a - lit(1, width: 8), width: 8)

        # Select result based on op
        result <= case_select(op, {
          0 => add_result,  # ADD
          1 => sub_result,  # SUB
          2 => and_result,  # AND
          3 => or_result,   # OR
          4 => xor_result,  # XOR
          5 => not_result,  # NOT
          6 => shl_result,  # SHL
          7 => shr_result,  # SHR
          8 => shr_result,  # SAR (simplified - proper SAR needs sign extension)
          9 => shl_result,  # ROL (simplified)
          10 => shr_result, # ROR (simplified)
          11 => mul_result, # MUL
          12 => div_result, # DIV
          13 => mod_result, # MOD
          14 => inc_result, # INC
          15 => dec_result  # DEC
        }, default: lit(0, width: 8))

        # Simplified flags - actual flag calculation is complex and done in propagate
        zero <= (result == lit(0, width: 8))
        negative <= result[7]
        cout <= lit(0, width: 1)      # Simplified
        overflow <= lit(0, width: 1)  # Simplified
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
        @outputs[:result] = Wire.new("#{@name}.result", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end

      # Override propagate for accurate simulation with all edge cases
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
