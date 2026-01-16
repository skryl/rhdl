# HDL Arithmetic Components
# Adders, subtractors, multipliers, and ALU with simulation behavior

module RHDL
  module HDL
    # Half Adder - adds 2 bits, produces sum and carry
    class HalfAdder < SimComponent
      def setup_ports
        input :a
        input :b
        output :sum
        output :cout
      end

      def propagate
        a = in_val(:a) & 1
        b = in_val(:b) & 1
        out_set(:sum, a ^ b)
        out_set(:cout, a & b)
      end
    end

    # Full Adder - adds 2 bits plus carry, produces sum and carry
    class FullAdder < SimComponent
      def setup_ports
        input :a
        input :b
        input :cin
        output :sum
        output :cout
      end

      def propagate
        a = in_val(:a) & 1
        b = in_val(:b) & 1
        cin = in_val(:cin) & 1

        # sum = a XOR b XOR cin
        sum = a ^ b ^ cin
        # cout = (a AND b) OR (cin AND (a XOR b))
        cout = (a & b) | (cin & (a ^ b))

        out_set(:sum, sum)
        out_set(:cout, cout)
      end
    end

    # Ripple Carry Adder - multi-bit adder
    class RippleCarryAdder < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :b, width: @width
        input :cin
        output :sum, width: @width
        output :cout
        output :overflow
      end

      def propagate
        a = in_val(:a)
        b = in_val(:b)
        cin = in_val(:cin) & 1

        result = a + b + cin
        mask = (1 << @width) - 1
        sum = result & mask
        cout = (result >> @width) & 1

        # Overflow for signed arithmetic
        a_sign = (a >> (@width - 1)) & 1
        b_sign = (b >> (@width - 1)) & 1
        sum_sign = (sum >> (@width - 1)) & 1
        overflow = ((a_sign == b_sign) && (sum_sign != a_sign)) ? 1 : 0

        out_set(:sum, sum)
        out_set(:cout, cout)
        out_set(:overflow, overflow)
      end
    end

    # Subtractor using 2's complement
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

    # Add-Subtract Unit
    class AddSub < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :b, width: @width
        input :sub      # 0 = add, 1 = subtract
        output :result, width: @width
        output :cout
        output :overflow
        output :zero
        output :negative
      end

      def propagate
        a = in_val(:a)
        b = in_val(:b)
        sub = in_val(:sub) & 1
        mask = (1 << @width) - 1

        if sub == 0
          result = a + b
        else
          result = a - b
        end

        final = result & mask
        cout = sub == 0 ? ((result >> @width) & 1) : (a < b ? 1 : 0)

        # Flags
        a_sign = (a >> (@width - 1)) & 1
        b_sign = (b >> (@width - 1)) & 1
        r_sign = (final >> (@width - 1)) & 1

        if sub == 0
          overflow = ((a_sign == b_sign) && (r_sign != a_sign)) ? 1 : 0
        else
          overflow = ((a_sign != b_sign) && (r_sign != a_sign)) ? 1 : 0
        end

        out_set(:result, final)
        out_set(:cout, cout)
        out_set(:overflow, overflow)
        out_set(:zero, final == 0 ? 1 : 0)
        out_set(:negative, r_sign)
      end
    end

    # Comparator
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

    # Multiplier (combinational, 8x8 -> 16)
    class Multiplier < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :b, width: @width
        output :product, width: @width * 2
      end

      def propagate
        a = in_val(:a)
        b = in_val(:b)
        product = a * b
        out_set(:product, product & ((1 << (@width * 2)) - 1))
      end
    end

    # Divider (combinational)
    class Divider < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :dividend, width: @width
        input :divisor, width: @width
        output :quotient, width: @width
        output :remainder, width: @width
        output :div_by_zero
      end

      def propagate
        dividend = in_val(:dividend)
        divisor = in_val(:divisor)

        if divisor == 0
          out_set(:quotient, 0)
          out_set(:remainder, 0)
          out_set(:div_by_zero, 1)
        else
          out_set(:quotient, dividend / divisor)
          out_set(:remainder, dividend % divisor)
          out_set(:div_by_zero, 0)
        end
      end
    end

    # Increment/Decrement Unit
    class IncDec < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :inc    # 1 = increment, 0 = decrement
        output :result, width: @width
        output :cout  # Carry/borrow
      end

      def propagate
        a = in_val(:a)
        mask = (1 << @width) - 1

        if in_val(:inc) == 1
          result = (a + 1) & mask
          cout = (a == mask) ? 1 : 0  # Overflow to 0
        else
          result = (a - 1) & mask
          cout = (a == 0) ? 1 : 0     # Underflow from 0
        end

        out_set(:result, result)
        out_set(:cout, cout)
      end
    end

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
