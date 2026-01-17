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

      behavior do
        w = param(:width)
        mask = (1 << w) - 1

        a_val = a.value
        b_val = b.value
        op_val = op.value
        cin_val = cin.value & 1

        res = 0
        cout_val = 0
        overflow_val = 0

        case op_val
        when 0  # ADD
          full = a_val + b_val + cin_val
          res = full & mask
          cout_val = (full >> w) & 1
          a_sign = (a_val >> (w - 1)) & 1
          b_sign = (b_val >> (w - 1)) & 1
          r_sign = (res >> (w - 1)) & 1
          overflow_val = ((a_sign == b_sign) && (r_sign != a_sign)) ? 1 : 0

        when 1  # SUB
          full = a_val - b_val - cin_val
          res = full & mask
          cout_val = (a_val < (b_val + cin_val)) ? 1 : 0
          a_sign = (a_val >> (w - 1)) & 1
          b_sign = (b_val >> (w - 1)) & 1
          r_sign = (res >> (w - 1)) & 1
          overflow_val = ((a_sign != b_sign) && (r_sign != a_sign)) ? 1 : 0

        when 2  # AND
          res = a_val & b_val

        when 3  # OR
          res = a_val | b_val

        when 4  # XOR
          res = a_val ^ b_val

        when 5  # NOT
          res = (~a_val) & mask

        when 6  # SHL
          shift_amt = b_val & 0x07
          full = a_val << shift_amt
          res = full & mask
          cout_val = (full >> w) & 1

        when 7  # SHR
          shift_amt = b_val & 0x07
          res = a_val >> shift_amt
          cout_val = shift_amt > 0 ? ((a_val >> (shift_amt - 1)) & 1) : 0

        when 8  # SAR (arithmetic right shift)
          shift_amt = b_val & 0x07
          sign = (a_val >> (w - 1)) & 1
          res = a_val >> shift_amt
          if sign == 1
            res |= (mask << (w - shift_amt)) & mask
          end
          cout_val = shift_amt > 0 ? ((a_val >> (shift_amt - 1)) & 1) : 0

        when 9  # ROL (rotate left)
          shift_amt = b_val & 0x07
          res = ((a_val << shift_amt) | (a_val >> (w - shift_amt))) & mask
          cout_val = (a_val >> (w - 1)) & 1

        when 10  # ROR (rotate right)
          shift_amt = b_val & 0x07
          res = ((a_val >> shift_amt) | (a_val << (w - shift_amt))) & mask
          cout_val = a_val & 1

        when 11  # MUL
          product = a_val * b_val
          res = product & mask
          cout_val = ((product >> w) != 0) ? 1 : 0

        when 12  # DIV
          if b_val == 0
            res = 0
            cout_val = 1
          else
            res = a_val / b_val
          end

        when 13  # MOD
          if b_val == 0
            res = a_val
            cout_val = 1
          else
            res = a_val % b_val
          end

        when 14  # INC
          res = (a_val + 1) & mask
          cout_val = (a_val == mask) ? 1 : 0
          overflow_val = (a_val == (mask >> 1)) ? 1 : 0

        when 15  # DEC
          res = (a_val - 1) & mask
          cout_val = (a_val == 0) ? 1 : 0
          overflow_val = (a_val == (1 << (w - 1))) ? 1 : 0
        end

        result <= res
        cout <= cout_val
        zero <= (res == 0 ? 1 : 0)
        negative <= ((res >> (w - 1)) & 1)
        overflow <= overflow_val
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
      end
    end
  end
end
