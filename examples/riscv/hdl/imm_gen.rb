# RV32I Immediate Generator
# Extracts and sign-extends immediate values from instructions
# Supports all RV32I instruction formats: I, S, B, U, J

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative 'constants'

module RISCV
  class ImmGen < RHDL::HDL::SimComponent
    include RHDL::DSL::Behavior

    input :inst, width: 32      # Full instruction
    output :imm, width: 32      # Sign-extended immediate

    behavior do
      # Extract opcode
      opcode = inst[6..0]

      # I-type immediate: inst[31:20]
      # Sign-extended from bit 11
      i_imm_raw = inst[31..20]
      i_sign = inst[31]
      i_imm = local(:i_imm,
        cat(i_sign.replicate(20), i_imm_raw),
        width: 32)

      # S-type immediate: inst[31:25] | inst[11:7]
      # Sign-extended from bit 11
      s_imm_raw = cat(inst[31..25], inst[11..7])
      s_sign = inst[31]
      s_imm = local(:s_imm,
        cat(s_sign.replicate(20), s_imm_raw),
        width: 32)

      # B-type immediate: inst[31] | inst[7] | inst[30:25] | inst[11:8] | 0
      # Sign-extended from bit 12, encoded in multiples of 2
      b_imm_raw = cat(inst[31], inst[7], inst[30..25], inst[11..8], lit(0, width: 1))
      b_sign = inst[31]
      b_imm = local(:b_imm,
        cat(b_sign.replicate(19), b_imm_raw),
        width: 32)

      # U-type immediate: inst[31:12] | 0000_0000_0000
      # No sign extension needed (upper 20 bits)
      u_imm = local(:u_imm,
        cat(inst[31..12], lit(0, width: 12)),
        width: 32)

      # J-type immediate: inst[31] | inst[19:12] | inst[20] | inst[30:21] | 0
      # Sign-extended from bit 20, encoded in multiples of 2
      j_imm_raw = cat(inst[31], inst[19..12], inst[20], inst[30..21], lit(0, width: 1))
      j_sign = inst[31]
      j_imm = local(:j_imm,
        cat(j_sign.replicate(11), j_imm_raw),
        width: 32)

      # Select immediate based on opcode
      imm <= case_select(opcode, {
        # I-type: JALR, LOAD, OP_IMM
        Opcode::JALR   => i_imm,
        Opcode::LOAD   => i_imm,
        Opcode::OP_IMM => i_imm,

        # S-type: STORE
        Opcode::STORE  => s_imm,

        # B-type: BRANCH
        Opcode::BRANCH => b_imm,

        # U-type: LUI, AUIPC
        Opcode::LUI    => u_imm,
        Opcode::AUIPC  => u_imm,

        # J-type: JAL
        Opcode::JAL    => j_imm,

        # SYSTEM, MISC_MEM use I-type encoding
        Opcode::SYSTEM   => i_imm,
        Opcode::MISC_MEM => i_imm
      }, default: lit(0, width: 32))
    end

    def self.verilog_module_name
      'riscv_imm_gen'
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: verilog_module_name))
    end
  end
end
