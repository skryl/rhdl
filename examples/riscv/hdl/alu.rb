# RV32I ALU - Fully Synthesizable
# Implements all RV32I arithmetic and logic operations
# Uses behavior DSL for Verilog export

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative 'constants'

module RISCV
  class ALU < RHDL::HDL::SimComponent
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

    input :a, width: 32       # First operand
    input :b, width: 32       # Second operand
    input :op, width: 4       # ALU operation

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
        OP_PASS_B => b
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
        OP_PASS_B => b
      }, default: add_result)
      zero <= alu_result == lit(0, width: 32)
    end

    def self.verilog_module_name
      'riscv_alu'
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: verilog_module_name))
    end
  end
end
