# RV32I/RV32M ALU - Fully Synthesizable
# Implements all RV32I arithmetic/logic ops and RV32M multiply/divide ops
# Uses behavior DSL for Verilog export

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative 'constants'

module RHDL
  module Examples
    module RISCV
      class ALU < RHDL::HDL::Component
    include RHDL::DSL::Behavior

    # ALU Operation codes
    OP_ADD   = AluOp::ADD
    OP_SUB   = AluOp::SUB
    OP_SLL   = AluOp::SLL
    OP_SLT   = AluOp::SLT
    OP_SLTU  = AluOp::SLTU
    OP_XOR   = AluOp::XOR
    OP_SRL   = AluOp::SRL
    OP_SRA   = AluOp::SRA
    OP_OR    = AluOp::OR
    OP_AND   = AluOp::AND
    OP_PASS_A = AluOp::PASS_A
    OP_PASS_B = AluOp::PASS_B
    OP_MUL   = AluOp::MUL
    OP_MULH  = AluOp::MULH
    OP_MULHSU = AluOp::MULHSU
    OP_MULHU = AluOp::MULHU
    OP_DIV   = AluOp::DIV
    OP_DIVU  = AluOp::DIVU
    OP_REM   = AluOp::REM
    OP_REMU  = AluOp::REMU
    OP_SH1ADD = AluOp::SH1ADD
    OP_SH2ADD = AluOp::SH2ADD
    OP_SH3ADD = AluOp::SH3ADD
    OP_ANDN  = AluOp::ANDN
    OP_ORN   = AluOp::ORN
    OP_XNOR  = AluOp::XNOR
    OP_MIN   = AluOp::MIN
    OP_MAX   = AluOp::MAX
    OP_MINU  = AluOp::MINU
    OP_MAXU  = AluOp::MAXU
    OP_PACK  = AluOp::PACK
    OP_PACKH = AluOp::PACKH
    OP_CLMUL = AluOp::CLMUL
    OP_CLMULH = AluOp::CLMULH
    OP_CLMULR = AluOp::CLMULR

    input :a, width: 32       # First operand
    input :b, width: 32       # Second operand
    input :op, width: 6       # ALU operation

    output :result, width: 32 # ALU result
    output :zero              # Result is zero

    behavior do
      # Compute all possible results
      add_result = local(:add_result, a + b, width: 32)
      sub_result = local(:sub_result, a - b, width: 32)
      xor_result = local(:xor_result, a ^ b, width: 32)
      or_result = local(:or_result, a | b, width: 32)
      and_result = local(:and_result, a & b, width: 32)

      # Shift amount is lower 5 bits of b
      shamt = local(:shamt, b[4..0], width: 5)

      # Shift left
      sll_result = local(:sll_result, a << shamt, width: 32)

      # Shift right logical
      srl_result = local(:srl_result, a >> shamt, width: 32)

      # Shift right arithmetic - replicate sign bit
      # When shifting right arithmetically, we need to preserve the sign
      sign_bit = a[31]
      # Create mask for sign extension
      # If sign is 1, we need to fill upper bits with 1s after shift
      # This creates a mask of 1s in the upper positions that were shifted
      sra_result = local(:sra_result,
        mux(sign_bit,
          (a >> shamt) | (~(lit(0xFFFFFFFF, width: 32) >> shamt)),
          a >> shamt
        ), width: 32)

      # Zba shifted-add address generation
      sh1add_result = local(:sh1add_result, a + (b << lit(1, width: 5)), width: 32)
      sh2add_result = local(:sh2add_result, a + (b << lit(2, width: 5)), width: 32)
      sh3add_result = local(:sh3add_result, a + (b << lit(3, width: 5)), width: 32)

      # Zbb subset operations
      andn_result = local(:andn_result, a & ~b, width: 32)
      orn_result = local(:orn_result, a | ~b, width: 32)
      xnor_result = local(:xnor_result, ~(a ^ b), width: 32)

      # Set less than (signed comparison)
      # Compare as signed: if signs differ, negative is less
      # If signs same, use unsigned subtraction
      a_sign = a[31]
      b_sign = b[31]
      slt_result = local(:slt_result,
        cat(lit(0, width: 31),
          mux(a_sign != b_sign,
            a_sign,  # Different signs: a < b if a is negative
            sub_result[31]  # Same signs: use subtraction result sign
          )
        ), width: 32)

      # Set less than unsigned
      sltu_result = local(:sltu_result,
        cat(lit(0, width: 31), a < b), width: 32)
      min_result = local(:min_result, mux(slt_result[0], a, b), width: 32)
      max_result = local(:max_result, mux(slt_result[0], b, a), width: 32)
      minu_result = local(:minu_result, mux(sltu_result[0], a, b), width: 32)
      maxu_result = local(:maxu_result, mux(sltu_result[0], b, a), width: 32)
      pack_result = local(
        :pack_result,
        (a & lit(0x0000FFFF, width: 32)) | ((b & lit(0x0000FFFF, width: 32)) << lit(16, width: 5)),
        width: 32
      )
      packh_result = local(
        :packh_result,
        (a & lit(0x000000FF, width: 32)) | ((b & lit(0x000000FF, width: 32)) << lit(8, width: 5)),
        width: 32
      )

      clmul_a64 = local(:clmul_a64, cat(lit(0, width: 32), a), width: 64)
      clmul_full_expr = lit(0, width: 64)
      32.times do |i|
        clmul_full_expr = clmul_full_expr ^ mux(
          b[i],
          clmul_a64 << lit(i, width: 6),
          lit(0, width: 64)
        )
      end
      clmul_full = local(:clmul_full, clmul_full_expr, width: 64)
      clmul_result = local(:clmul_result, clmul_full[31..0], width: 32)
      clmulh_result = local(:clmulh_result, clmul_full[63..32], width: 32)
      clmulr_result = local(:clmulr_result, clmul_full[62..31], width: 32)

      # ------------------------------------------------------------------
      # RV32M: Multiply variants
      # ------------------------------------------------------------------
      a_sign = a[31]
      b_sign = b[31]

      a_signed_64 = local(:a_signed_64,
        cat(mux(a_sign, lit(0xFFFFFFFF, width: 32), lit(0, width: 32)), a), width: 64)
      b_signed_64 = local(:b_signed_64,
        cat(mux(b_sign, lit(0xFFFFFFFF, width: 32), lit(0, width: 32)), b), width: 64)
      a_unsigned_64 = local(:a_unsigned_64, cat(lit(0, width: 32), a), width: 64)
      b_unsigned_64 = local(:b_unsigned_64, cat(lit(0, width: 32), b), width: 64)

      mul_ss_full = local(:mul_ss_full, a_signed_64 * b_signed_64, width: 64)
      mul_su_full = local(:mul_su_full, a_signed_64 * b_unsigned_64, width: 64)
      mul_uu_full = local(:mul_uu_full, a_unsigned_64 * b_unsigned_64, width: 64)

      mul_result = local(:mul_result, mul_uu_full[31..0], width: 32)
      mulh_result = local(:mulh_result, mul_ss_full[63..32], width: 32)
      mulhsu_result = local(:mulhsu_result, mul_su_full[63..32], width: 32)
      mulhu_result = local(:mulhu_result, mul_uu_full[63..32], width: 32)

      # ------------------------------------------------------------------
      # RV32M: Divide/remainder variants
      # ------------------------------------------------------------------
      div_by_zero = b == lit(0, width: 32)
      div_overflow = (a == lit(0x80000000, width: 32)) & (b == lit(0xFFFFFFFF, width: 32))

      a_abs = local(:a_abs, mux(a_sign, (~a + lit(1, width: 32)), a), width: 32)
      b_abs = local(:b_abs, mux(b_sign, (~b + lit(1, width: 32)), b), width: 32)

      abs_q = local(:abs_q, a_abs / b_abs, width: 32)
      abs_r = local(:abs_r, a_abs % b_abs, width: 32)

      q_neg = local(:q_neg, (~abs_q + lit(1, width: 32)), width: 32)
      r_neg = local(:r_neg, (~abs_r + lit(1, width: 32)), width: 32)

      signed_q = local(:signed_q, mux(a_sign ^ b_sign, q_neg, abs_q), width: 32)
      signed_r = local(:signed_r, mux(a_sign, r_neg, abs_r), width: 32)

      div_result = local(:div_result,
        mux(div_by_zero,
          lit(0xFFFFFFFF, width: 32),
          mux(div_overflow, lit(0x80000000, width: 32), signed_q)
        ), width: 32)

      rem_result = local(:rem_result,
        mux(div_by_zero,
          a,
          mux(div_overflow, lit(0, width: 32), signed_r)
        ), width: 32)

      divu_q = local(:divu_q, a / b, width: 32)
      divu_r = local(:divu_r, a % b, width: 32)
      divu_result = local(:divu_result, mux(div_by_zero, lit(0xFFFFFFFF, width: 32), divu_q), width: 32)
      remu_result = local(:remu_result, mux(div_by_zero, a, divu_r), width: 32)

      # Result multiplexer
      result <= case_select(op, {
        OP_ADD   => add_result,
        OP_SUB   => sub_result,
        OP_SLL   => sll_result,
        OP_SLT   => slt_result,
        OP_SLTU  => sltu_result,
        OP_XOR   => xor_result,
        OP_SRL   => srl_result,
        OP_SRA   => sra_result,
        OP_OR    => or_result,
        OP_AND   => and_result,
        OP_PASS_A => a,
        OP_PASS_B => b,
        OP_MUL   => mul_result,
        OP_MULH  => mulh_result,
        OP_MULHSU => mulhsu_result,
        OP_MULHU => mulhu_result,
        OP_DIV   => div_result,
        OP_DIVU  => divu_result,
        OP_REM   => rem_result,
        OP_REMU  => remu_result,
        OP_SH1ADD => sh1add_result,
        OP_SH2ADD => sh2add_result,
        OP_SH3ADD => sh3add_result,
        OP_ANDN => andn_result,
        OP_ORN => orn_result,
        OP_XNOR => xnor_result,
        OP_MIN => min_result,
        OP_MAX => max_result,
        OP_MINU => minu_result,
        OP_MAXU => maxu_result,
        OP_PACK => pack_result,
        OP_PACKH => packh_result,
        OP_CLMUL => clmul_result,
        OP_CLMULH => clmulh_result,
        OP_CLMULR => clmulr_result
      }, default: add_result)

      # Zero flag - check if all bits are zero
      alu_result = case_select(op, {
        OP_ADD   => add_result,
        OP_SUB   => sub_result,
        OP_SLL   => sll_result,
        OP_SLT   => slt_result,
        OP_SLTU  => sltu_result,
        OP_XOR   => xor_result,
        OP_SRL   => srl_result,
        OP_SRA   => sra_result,
        OP_OR    => or_result,
        OP_AND   => and_result,
        OP_PASS_A => a,
        OP_PASS_B => b,
        OP_MUL   => mul_result,
        OP_MULH  => mulh_result,
        OP_MULHSU => mulhsu_result,
        OP_MULHU => mulhu_result,
        OP_DIV   => div_result,
        OP_DIVU  => divu_result,
        OP_REM   => rem_result,
        OP_REMU  => remu_result,
        OP_SH1ADD => sh1add_result,
        OP_SH2ADD => sh2add_result,
        OP_SH3ADD => sh3add_result,
        OP_ANDN => andn_result,
        OP_ORN => orn_result,
        OP_XNOR => xnor_result,
        OP_MIN => min_result,
        OP_MAX => max_result,
        OP_MINU => minu_result,
        OP_MAXU => maxu_result,
        OP_PACK => pack_result,
        OP_PACKH => packh_result,
        OP_CLMUL => clmul_result,
        OP_CLMULH => clmulh_result,
        OP_CLMULR => clmulr_result
      }, default: add_result)
      zero <= alu_result == lit(0, width: 32)
    end

      end
    end
  end
end
