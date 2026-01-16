# MOS 6502 Arithmetic Logic Unit
# Supports all 6502 arithmetic and logic operations including BCD mode
# Combinational - can be synthesized as combinational logic

module MOS6502
  class ALU < RHDL::HDL::SimComponent
    # ALU Operation codes
    OP_ADC = 0x00  # Add with carry
    OP_SBC = 0x01  # Subtract with borrow (carry inverted)
    OP_AND = 0x02  # Bitwise AND
    OP_ORA = 0x03  # Bitwise OR
    OP_EOR = 0x04  # Bitwise XOR
    OP_ASL = 0x05  # Arithmetic shift left
    OP_LSR = 0x06  # Logical shift right
    OP_ROL = 0x07  # Rotate left through carry
    OP_ROR = 0x08  # Rotate right through carry
    OP_INC = 0x09  # Increment
    OP_DEC = 0x0A  # Decrement
    OP_CMP = 0x0B  # Compare (A - M, flags only)
    OP_BIT = 0x0C  # Bit test
    OP_TST = 0x0D  # Pass through A (for TXA, TYA, TAX, TAY, LDA, etc.)
    OP_NOP = 0x0F  # No operation

    port_input :a, width: 8         # Accumulator or first operand
    port_input :b, width: 8         # Memory operand or second operand
    port_input :c_in                # Carry input
    port_input :d_flag              # Decimal mode flag
    port_input :op, width: 4        # Operation select

    port_output :result, width: 8   # ALU result
    port_output :n                  # Negative flag (bit 7 of result)
    port_output :z                  # Zero flag
    port_output :c                  # Carry flag
    port_output :v                  # Overflow flag

    # Note: Complex BCD logic and case statements make behavior DSL impractical
    # This is combinational but uses manual propagate for clarity
    def propagate
      a = in_val(:a) & 0xFF
      b = in_val(:b) & 0xFF
      c_in = in_val(:c_in) & 1
      d_flag = in_val(:d_flag) & 1
      op = in_val(:op) & 0x0F

      result = 0
      c_out = 0
      v_out = 0
      n_out = 0
      z_out = 0

      case op
      when OP_ADC
        if d_flag == 1
          # BCD addition
          result, c_out, v_out = bcd_add(a, b, c_in)
        else
          # Binary addition
          sum = a + b + c_in
          result = sum & 0xFF
          c_out = (sum >> 8) & 1

          # V flag: set if signs of operands match but result sign differs
          a_sign = (a >> 7) & 1
          b_sign = (b >> 7) & 1
          r_sign = (result >> 7) & 1
          v_out = ((a_sign == b_sign) && (r_sign != a_sign)) ? 1 : 0
        end
        n_out = (result >> 7) & 1
        z_out = (result == 0) ? 1 : 0

      when OP_SBC
        if d_flag == 1
          # BCD subtraction
          result, c_out, v_out = bcd_sub(a, b, c_in)
        else
          # Binary subtraction: A - M - !C = A + ~M + C
          b_comp = (~b) & 0xFF
          sum = a + b_comp + c_in
          result = sum & 0xFF
          c_out = (sum >> 8) & 1  # Carry set if no borrow

          # V flag for subtraction
          a_sign = (a >> 7) & 1
          b_sign = (b >> 7) & 1
          r_sign = (result >> 7) & 1
          v_out = ((a_sign != b_sign) && (r_sign != a_sign)) ? 1 : 0
        end
        n_out = (result >> 7) & 1
        z_out = (result == 0) ? 1 : 0

      when OP_AND
        result = a & b
        n_out = (result >> 7) & 1
        z_out = (result == 0) ? 1 : 0

      when OP_ORA
        result = a | b
        n_out = (result >> 7) & 1
        z_out = (result == 0) ? 1 : 0

      when OP_EOR
        result = a ^ b
        n_out = (result >> 7) & 1
        z_out = (result == 0) ? 1 : 0

      when OP_ASL
        # Shift A left, bit 7 goes to carry
        result = (a << 1) & 0xFF
        c_out = (a >> 7) & 1
        n_out = (result >> 7) & 1
        z_out = (result == 0) ? 1 : 0

      when OP_LSR
        # Logical shift right, bit 0 goes to carry
        result = a >> 1
        c_out = a & 1
        n_out = 0  # Always 0 after LSR
        z_out = (result == 0) ? 1 : 0

      when OP_ROL
        # Rotate left through carry
        result = ((a << 1) | c_in) & 0xFF
        c_out = (a >> 7) & 1
        n_out = (result >> 7) & 1
        z_out = (result == 0) ? 1 : 0

      when OP_ROR
        # Rotate right through carry
        result = (a >> 1) | (c_in << 7)
        c_out = a & 1
        n_out = (result >> 7) & 1
        z_out = (result == 0) ? 1 : 0

      when OP_INC
        result = (a + 1) & 0xFF
        n_out = (result >> 7) & 1
        z_out = (result == 0) ? 1 : 0

      when OP_DEC
        result = (a - 1) & 0xFF
        n_out = (result >> 7) & 1
        z_out = (result == 0) ? 1 : 0

      when OP_CMP
        # Compare: A - M, sets N, Z, C but doesn't store result
        diff = a - b
        result = diff & 0xFF
        c_out = (a >= b) ? 1 : 0
        n_out = (result >> 7) & 1
        z_out = (a == b) ? 1 : 0

      when OP_BIT
        # BIT test: Z is set based on A AND M, but N and V come from M
        # Result is not stored
        result = a  # Don't modify accumulator
        n_out = (b >> 7) & 1  # N = bit 7 of memory
        v_out = (b >> 6) & 1  # V = bit 6 of memory
        z_out = ((a & b) == 0) ? 1 : 0

      when OP_TST
        # Pass through A (for transfers and loads)
        result = a
        n_out = (result >> 7) & 1
        z_out = (result == 0) ? 1 : 0

      when OP_NOP
        result = a
        # Flags unchanged - keep whatever was there
        n_out = 0
        z_out = 0
        c_out = c_in
      end

      out_set(:result, result)
      out_set(:n, n_out)
      out_set(:z, z_out)
      out_set(:c, c_out)
      out_set(:v, v_out)
    end

    private

    # BCD addition with carry
    def bcd_add(a, b, c)
      # Split into nibbles
      al = a & 0x0F
      ah = (a >> 4) & 0x0F
      bl = b & 0x0F
      bh = (b >> 4) & 0x0F

      # Add low nibble
      sum_l = al + bl + c
      carry_l = 0
      if sum_l > 9
        sum_l = (sum_l + 6) & 0x0F
        carry_l = 1
      end

      # Add high nibble
      sum_h = ah + bh + carry_l
      carry_h = 0
      if sum_h > 9
        sum_h = (sum_h + 6) & 0x0F
        carry_h = 1
      end

      result = (sum_h << 4) | sum_l

      # V flag calculation for BCD (simplified)
      a_sign = (a >> 7) & 1
      b_sign = (b >> 7) & 1
      r_sign = (result >> 7) & 1
      v = ((a_sign == b_sign) && (r_sign != a_sign)) ? 1 : 0

      [result, carry_h, v]
    end

    # BCD subtraction with borrow
    def bcd_sub(a, b, c)
      # Split into nibbles
      al = a & 0x0F
      ah = (a >> 4) & 0x0F
      bl = b & 0x0F
      bh = (b >> 4) & 0x0F

      # c is the inverted borrow (1 = no borrow)
      borrow = (c == 1) ? 0 : 1

      # Subtract low nibble
      diff_l = al - bl - borrow
      borrow_l = 0
      if diff_l < 0
        diff_l = (diff_l + 10) & 0x0F
        borrow_l = 1
      end

      # Subtract high nibble
      diff_h = ah - bh - borrow_l
      borrow_h = 0
      if diff_h < 0
        diff_h = (diff_h + 10) & 0x0F
        borrow_h = 1
      end

      result = (diff_h << 4) | diff_l
      carry = (borrow_h == 0) ? 1 : 0  # C set if no borrow

      # V flag calculation for BCD (simplified)
      a_sign = (a >> 7) & 1
      b_sign = (b >> 7) & 1
      r_sign = (result >> 7) & 1
      v = ((a_sign != b_sign) && (r_sign != a_sign)) ? 1 : 0

      [result, carry, v]
    end
  end
end
