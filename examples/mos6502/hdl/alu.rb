# MOS 6502 ALU - Fully Synthesizable DSL Version
# Complete implementation with Binary Coded Decimal (BCD) mode
# Uses behavior DSL for Verilog/VHDL export

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'

module MOS6502
  class ALU < RHDL::HDL::Component
    include RHDL::DSL::Behavior

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
    OP_CMP = 0x0B  # Compare
    OP_BIT = 0x0C  # Bit test
    OP_TST = 0x0D  # Pass through A
    OP_NOP = 0x0F  # No operation

    input :a, width: 8
    input :b, width: 8
    input :c_in
    input :d_flag
    input :op, width: 4

    output :result, width: 8
    output :n
    output :z
    output :c
    output :v

    # Behavior block for combinational synthesis
    behavior do
      # Binary arithmetic - 9-bit for carry detection
      bin_sum = local(:bin_sum,
        cat(lit(0, width: 1), a) + cat(lit(0, width: 1), b) + cat(lit(0, width: 8), c_in),
        width: 9)
      b_inv = local(:b_inv, ~b, width: 8)
      bin_diff = local(:bin_diff,
        cat(lit(0, width: 1), a) + cat(lit(0, width: 1), b_inv) + cat(lit(0, width: 8), c_in),
        width: 9)

      # BCD arithmetic - nibble extraction
      al = local(:al, a[3..0], width: 4)
      ah = local(:ah, a[7..4], width: 4)
      bl = local(:bl, b[3..0], width: 4)
      bh = local(:bh, b[7..4], width: 4)

      # BCD add - low nibble
      sum_l_raw = local(:sum_l_raw,
        cat(lit(0, width: 1), al) + cat(lit(0, width: 1), bl) + cat(lit(0, width: 4), c_in),
        width: 5)
      carry_l = local(:carry_l, sum_l_raw > lit(9, width: 5), width: 1)
      adj_l = local(:adj_l,
        mux(carry_l, (sum_l_raw + lit(6, width: 5))[3..0], sum_l_raw[3..0]),
        width: 4)

      # BCD add - high nibble
      sum_h_raw = local(:sum_h_raw,
        cat(lit(0, width: 1), ah) + cat(lit(0, width: 1), bh) + cat(lit(0, width: 4), carry_l),
        width: 5)
      carry_h = local(:carry_h, sum_h_raw > lit(9, width: 5), width: 1)
      adj_h = local(:adj_h,
        mux(carry_h, (sum_h_raw + lit(6, width: 5))[3..0], sum_h_raw[3..0]),
        width: 4)

      # BCD subtract - low nibble
      diff_l_raw = local(:diff_l_raw,
        cat(lit(0, width: 1), al) - cat(lit(0, width: 1), bl) - cat(lit(0, width: 4), ~c_in),
        width: 5)
      borrow_l = local(:borrow_l, diff_l_raw[4], width: 1)
      sub_adj_l = local(:sub_adj_l,
        mux(borrow_l, (diff_l_raw + lit(10, width: 5))[3..0], diff_l_raw[3..0]),
        width: 4)

      # BCD subtract - high nibble
      diff_h_raw = local(:diff_h_raw,
        cat(lit(0, width: 1), ah) - cat(lit(0, width: 1), bh) - cat(lit(0, width: 4), borrow_l),
        width: 5)
      borrow_h = local(:borrow_h, diff_h_raw[4], width: 1)
      sub_adj_h = local(:sub_adj_h,
        mux(borrow_h, (diff_h_raw + lit(10, width: 5))[3..0], diff_h_raw[3..0]),
        width: 4)

      # BCD results
      bcd_add_result = local(:bcd_add_result, cat(adj_h, adj_l), width: 8)
      bcd_sub_result = local(:bcd_sub_result, cat(sub_adj_h, sub_adj_l), width: 8)

      # Simple operation results
      and_result = local(:and_result, a & b, width: 8)
      ora_result = local(:ora_result, a | b, width: 8)
      eor_result = local(:eor_result, a ^ b, width: 8)
      asl_result = local(:asl_result, cat(a[6..0], lit(0, width: 1)), width: 8)
      lsr_result = local(:lsr_result, cat(lit(0, width: 1), a[7..1]), width: 8)
      rol_result = local(:rol_result, cat(a[6..0], c_in), width: 8)
      ror_result = local(:ror_result, cat(c_in, a[7..1]), width: 8)
      inc_result = local(:inc_result, (a + lit(1, width: 8))[7..0], width: 8)
      dec_result = local(:dec_result, (a - lit(1, width: 8))[7..0], width: 8)
      cmp_result = local(:cmp_result, (a - b)[7..0], width: 8)

      # ADC/SBC final results
      adc_result = local(:adc_result, mux(d_flag, bcd_add_result, bin_sum[7..0]), width: 8)
      sbc_result = local(:sbc_result, mux(d_flag, bcd_sub_result, bin_diff[7..0]), width: 8)

      # Result output - main case select
      result <= case_select(op, {
        OP_ADC => adc_result,
        OP_SBC => sbc_result,
        OP_AND => and_result,
        OP_ORA => ora_result,
        OP_EOR => eor_result,
        OP_ASL => asl_result,
        OP_LSR => lsr_result,
        OP_ROL => rol_result,
        OP_ROR => ror_result,
        OP_INC => inc_result,
        OP_DEC => dec_result,
        OP_CMP => cmp_result,
        OP_BIT => a,
        OP_TST => b,  # Pass through B for load instructions
        OP_NOP => a
      }, default: a)

      # N flag (negative)
      n <= case_select(op, {
        OP_ADC => adc_result[7],
        OP_SBC => sbc_result[7],
        OP_AND => and_result[7],
        OP_ORA => ora_result[7],
        OP_EOR => eor_result[7],
        OP_ASL => asl_result[7],
        OP_LSR => lit(0, width: 1),
        OP_ROL => rol_result[7],
        OP_ROR => ror_result[7],
        OP_INC => inc_result[7],
        OP_DEC => dec_result[7],
        OP_CMP => cmp_result[7],
        OP_BIT => b[7],
        OP_TST => b[7]  # Test B for load instructions
      }, default: 0)

      # Z flag (zero)
      z <= case_select(op, {
        OP_ADC => adc_result == lit(0, width: 8),
        OP_SBC => sbc_result == lit(0, width: 8),
        OP_AND => and_result == lit(0, width: 8),
        OP_ORA => ora_result == lit(0, width: 8),
        OP_EOR => eor_result == lit(0, width: 8),
        OP_ASL => asl_result == lit(0, width: 8),
        OP_LSR => lsr_result == lit(0, width: 8),
        OP_ROL => rol_result == lit(0, width: 8),
        OP_ROR => ror_result == lit(0, width: 8),
        OP_INC => inc_result == lit(0, width: 8),
        OP_DEC => dec_result == lit(0, width: 8),
        OP_CMP => a == b,
        OP_BIT => (a & b) == lit(0, width: 8),
        OP_TST => b == lit(0, width: 8)  # Test B for load instructions
      }, default: 0)

      # C flag (carry)
      c <= case_select(op, {
        OP_ADC => mux(d_flag, carry_h, bin_sum[8]),
        OP_SBC => mux(d_flag, ~borrow_h, bin_diff[8]),
        OP_ASL => a[7],
        OP_LSR => a[0],
        OP_ROL => a[7],
        OP_ROR => a[0],
        OP_CMP => a >= b,
        OP_NOP => c_in
      }, default: 0)

      # V flag (overflow) - only for ADC, SBC, BIT
      # V = (a[7] == b[7]) && (result[7] != a[7]) for ADC
      # V = (a[7] != b[7]) && (result[7] != a[7]) for SBC
      adc_v = (a[7] == b[7]) & (adc_result[7] != a[7])
      sbc_v = (a[7] != b[7]) & (sbc_result[7] != a[7])

      v <= case_select(op, {
        OP_ADC => adc_v,
        OP_SBC => sbc_v,
        OP_BIT => b[6]
      }, default: 0)
    end

  end
end
