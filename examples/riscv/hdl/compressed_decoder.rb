# RV32C decompressor (subset)
# Expands supported 16-bit compressed instructions into canonical 32-bit RV32I forms.
# Unsupported/reserved compressed encodings are mapped to an illegal SYSTEM encoding.
#
# Supported compressed instructions:
# - C.ADDI / C.NOP
# - C.LI
# - C.LW / C.SW
# - C.J / C.JAL (RV32)
# - C.BEQZ / C.BNEZ
# - C.MV / C.ADD
# - C.JR / C.JALR
# - C.EBREAK

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative 'constants'

module RHDL
  module Examples
    module RISCV
      class CompressedDecoder < RHDL::HDL::Component
        include RHDL::DSL::Behavior

        input :inst_word, width: 32

        output :inst_out, width: 32
        output :is_compressed
        output :pc_step, width: 32

        behavior do
          c_inst = inst_word[15..0]
          quadrant = c_inst[1..0]
          funct3 = c_inst[15..13]
          rd = c_inst[11..7]
          rs2 = c_inst[6..2]
          rs1p = cat(lit(0b01, width: 2), c_inst[9..7])
          rdp = cat(lit(0b01, width: 2), c_inst[4..2])
          rs2p = rdp

          is_c = local(:is_c, quadrant != lit(0b11, width: 2), width: 1)
          is_q0 = quadrant == lit(0b00, width: 2)
          is_q1 = quadrant == lit(0b01, width: 2)
          is_q2 = quadrant == lit(0b10, width: 2)

          ci_imm12 = local(:ci_imm12,
                           cat(c_inst[12].replicate(6), c_inst[12], c_inst[6..2]),
                           width: 12)
          lw_uimm12 = local(:lw_uimm12,
                            cat(lit(0, width: 5), c_inst[5], c_inst[12..10], c_inst[6], lit(0, width: 2)),
                            width: 12)
          sw_imm12 = local(:sw_imm12,
                           cat(lit(0, width: 5), c_inst[5], c_inst[12..10], c_inst[6], lit(0, width: 2)),
                           width: 12)
          j_imm12 = local(:j_imm12,
                          cat(c_inst[12], c_inst[8], c_inst[10..9], c_inst[6], c_inst[7], c_inst[2],
                              c_inst[11], c_inst[5..3], lit(0, width: 1)),
                          width: 12)
          j_imm21 = local(:j_imm21, cat(c_inst[12].replicate(9), j_imm12), width: 21)
          b_imm9 = local(:b_imm9,
                         cat(c_inst[12], c_inst[6..5], c_inst[2], c_inst[11..10], c_inst[4..3], lit(0, width: 1)),
                         width: 9)
          b_imm13 = local(:b_imm13, cat(c_inst[12].replicate(4), b_imm9), width: 13)

          addi_inst = local(:addi_inst,
                            cat(ci_imm12, rd, lit(Funct3::ADD_SUB, width: 3), rd, lit(Opcode::OP_IMM, width: 7)),
                            width: 32)
          li_inst = local(:li_inst,
                          cat(ci_imm12, lit(0, width: 5), lit(Funct3::ADD_SUB, width: 3), rd, lit(Opcode::OP_IMM, width: 7)),
                          width: 32)
          lw_inst = local(:lw_inst,
                          cat(lw_uimm12, rs1p, lit(Funct3::WORD, width: 3), rdp, lit(Opcode::LOAD, width: 7)),
                          width: 32)
          sw_inst = local(:sw_inst,
                          cat(sw_imm12[11..5], rs2p, rs1p, lit(Funct3::WORD, width: 3),
                              sw_imm12[4..0], lit(Opcode::STORE, width: 7)),
                          width: 32)
          j_inst = local(:j_inst,
                         cat(j_imm21[20], j_imm21[10..1], j_imm21[11], j_imm21[19..12],
                             lit(0, width: 5), lit(Opcode::JAL, width: 7)),
                         width: 32)
          jal_inst = local(:jal_inst,
                           cat(j_imm21[20], j_imm21[10..1], j_imm21[11], j_imm21[19..12],
                               lit(1, width: 5), lit(Opcode::JAL, width: 7)),
                           width: 32)
          beqz_inst = local(:beqz_inst,
                            cat(b_imm13[12], b_imm13[10..5], lit(0, width: 5), rs1p, lit(Funct3::BEQ, width: 3),
                                b_imm13[4..1], b_imm13[11], lit(Opcode::BRANCH, width: 7)),
                            width: 32)
          bnez_inst = local(:bnez_inst,
                            cat(b_imm13[12], b_imm13[10..5], lit(0, width: 5), rs1p, lit(Funct3::BNE, width: 3),
                                b_imm13[4..1], b_imm13[11], lit(Opcode::BRANCH, width: 7)),
                            width: 32)
          mv_inst = local(:mv_inst,
                          cat(lit(Funct7::NORMAL, width: 7), rs2, lit(0, width: 5),
                              lit(Funct3::ADD_SUB, width: 3), rd, lit(Opcode::OP, width: 7)),
                          width: 32)
          add_inst = local(:add_inst,
                           cat(lit(Funct7::NORMAL, width: 7), rs2, rd,
                               lit(Funct3::ADD_SUB, width: 3), rd, lit(Opcode::OP, width: 7)),
                           width: 32)
          jr_inst = local(:jr_inst,
                          cat(lit(0, width: 12), rd, lit(Funct3::ADD_SUB, width: 3), lit(0, width: 5), lit(Opcode::JALR, width: 7)),
                          width: 32)
          jalr_inst = local(:jalr_inst,
                            cat(lit(0, width: 12), rd, lit(Funct3::ADD_SUB, width: 3), lit(1, width: 5), lit(Opcode::JALR, width: 7)),
                            width: 32)
          ebreak_inst = local(:ebreak_inst,
                              cat(lit(1, width: 12), lit(0, width: 5), lit(0, width: 3), lit(0, width: 5), lit(Opcode::SYSTEM, width: 7)),
                              width: 32)
          nop_inst = local(:nop_inst,
                           cat(lit(0, width: 12), lit(0, width: 5), lit(Funct3::ADD_SUB, width: 3), lit(0, width: 5),
                               lit(Opcode::OP_IMM, width: 7)),
                           width: 32)
          illegal_inst = local(:illegal_inst,
                               cat(lit(0x7FF, width: 12), lit(0, width: 5), lit(0, width: 3), lit(0, width: 5),
                                   lit(Opcode::SYSTEM, width: 7)),
                               width: 32)

          c_bit12 = c_inst[12]
          rd_zero = rd == lit(0, width: 5)
          rs2_zero = rs2 == lit(0, width: 5)

          is_c_addi = local(:is_c_addi, is_q1 & (funct3 == lit(0b000, width: 3)), width: 1)
          is_c_li_illegal = local(:is_c_li_illegal, is_q1 & (funct3 == lit(0b010, width: 3)) & rd_zero, width: 1)
          is_c_li = local(:is_c_li, is_q1 & (funct3 == lit(0b010, width: 3)) & ~rd_zero, width: 1)
          is_c_lw = local(:is_c_lw, is_q0 & (funct3 == lit(0b010, width: 3)), width: 1)
          is_c_sw = local(:is_c_sw, is_q0 & (funct3 == lit(0b110, width: 3)), width: 1)
          is_c_j = local(:is_c_j, is_q1 & (funct3 == lit(0b101, width: 3)), width: 1)
          is_c_jal = local(:is_c_jal, is_q1 & (funct3 == lit(0b001, width: 3)), width: 1)
          is_c_beqz = local(:is_c_beqz, is_q1 & (funct3 == lit(0b110, width: 3)), width: 1)
          is_c_bnez = local(:is_c_bnez, is_q1 & (funct3 == lit(0b111, width: 3)), width: 1)
          is_c_jr = local(:is_c_jr, is_q2 & (funct3 == lit(0b100, width: 3)) & (c_bit12 == lit(0, width: 1)) & rs2_zero & ~rd_zero, width: 1)
          is_c_mv = local(:is_c_mv, is_q2 & (funct3 == lit(0b100, width: 3)) & (c_bit12 == lit(0, width: 1)) & ~rs2_zero & ~rd_zero, width: 1)
          is_c_jalr = local(:is_c_jalr, is_q2 & (funct3 == lit(0b100, width: 3)) & (c_bit12 == lit(1, width: 1)) & rs2_zero & ~rd_zero, width: 1)
          is_c_add = local(:is_c_add, is_q2 & (funct3 == lit(0b100, width: 3)) & (c_bit12 == lit(1, width: 1)) & ~rs2_zero & ~rd_zero, width: 1)
          is_c_ebreak = local(:is_c_ebreak, is_q2 & (funct3 == lit(0b100, width: 3)) & (c_bit12 == lit(1, width: 1)) & rs2_zero & rd_zero, width: 1)

          c_decompressed_expr = nop_inst
          c_decompressed_expr = mux(is_c_ebreak, ebreak_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_add, add_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_jalr, jalr_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_mv, mv_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_jr, jr_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_bnez, bnez_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_beqz, beqz_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_jal, jal_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_j, j_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_sw, sw_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_lw, lw_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_li, li_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_addi, addi_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_li_illegal, illegal_inst, c_decompressed_expr)

          c_decompressed = local(:c_decompressed, c_decompressed_expr, width: 32)

          inst_out <= mux(is_c, c_decompressed, inst_word)
          is_compressed <= is_c
          pc_step <= mux(is_c, lit(2, width: 32), lit(4, width: 32))
        end
      end
    end
  end
end
