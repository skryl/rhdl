# RV32C decompressor (subset)
# Expands supported 16-bit compressed instructions into canonical 32-bit RV32I forms.
# Unsupported/reserved compressed encodings are mapped to an illegal SYSTEM encoding.
#
# Supported compressed instructions:
# - C.ADDI4SPN
# - C.ADDI / C.NOP
# - C.LI / C.LUI / C.ADDI16SP
# - C.LW / C.SW
# - C.SLLI / C.SRLI / C.SRAI / C.ANDI
# - C.SUB / C.XOR / C.OR / C.AND
# - C.J / C.JAL (RV32)
# - C.BEQZ / C.BNEZ
# - C.MV / C.ADD
# - C.JR / C.JALR
# - C.LWSP / C.SWSP
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

          ciw_uimm12 = local(:ciw_uimm12,
                             cat(lit(0, width: 2), c_inst[10..7], c_inst[12..11], c_inst[5], c_inst[6],
                                 lit(0, width: 2)),
                             width: 12)
          ci_imm12 = local(:ci_imm12,
                           cat(c_inst[12].replicate(6), c_inst[12], c_inst[6..2]),
                           width: 12)
          addi16sp_imm12 = local(:addi16sp_imm12,
                                 cat(c_inst[12].replicate(2), c_inst[12], c_inst[4..3], c_inst[5], c_inst[2], c_inst[6],
                                     lit(0, width: 4)),
                                 width: 12)
          lwsp_uimm12 = local(:lwsp_uimm12,
                              cat(lit(0, width: 4), c_inst[3..2], c_inst[12], c_inst[6..4], lit(0, width: 2)),
                              width: 12)
          swsp_imm12 = local(:swsp_imm12,
                             cat(lit(0, width: 4), c_inst[8..7], c_inst[12..9], lit(0, width: 2)),
                             width: 12)
          lui_uimm20 = local(:lui_uimm20,
                             cat(c_inst[12].replicate(14), c_inst[12], c_inst[6..2]),
                             width: 20)
          lw_uimm12 = local(:lw_uimm12,
                            cat(lit(0, width: 5), c_inst[5], c_inst[12..10], c_inst[6], lit(0, width: 2)),
                            width: 12)
          sw_imm12 = local(:sw_imm12,
                           cat(lit(0, width: 5), c_inst[5], c_inst[12..10], c_inst[6], lit(0, width: 2)),
                           width: 12)
          slli_imm12 = local(:slli_imm12, cat(lit(0b0000000, width: 7), c_inst[6..2]), width: 12)
          srli_imm12 = local(:srli_imm12, cat(lit(0b0000000, width: 7), c_inst[6..2]), width: 12)
          srai_imm12 = local(:srai_imm12, cat(lit(0b0100000, width: 7), c_inst[6..2]), width: 12)
          j_imm12 = local(:j_imm12,
                          cat(c_inst[12], c_inst[8], c_inst[10..9], c_inst[6], c_inst[7], c_inst[2],
                              c_inst[11], c_inst[5..3], lit(0, width: 1)),
                          width: 12)
          j_imm21 = local(:j_imm21, cat(c_inst[12].replicate(9), j_imm12), width: 21)
          b_imm9 = local(:b_imm9,
                         cat(c_inst[12], c_inst[6..5], c_inst[2], c_inst[11..10], c_inst[4..3], lit(0, width: 1)),
                         width: 9)
          b_imm13 = local(:b_imm13, cat(c_inst[12].replicate(4), b_imm9), width: 13)

          addi4spn_inst = local(:addi4spn_inst,
                                cat(ciw_uimm12, lit(2, width: 5), lit(Funct3::ADD_SUB, width: 3), rdp,
                                    lit(Opcode::OP_IMM, width: 7)),
                                width: 32)
          addi_inst = local(:addi_inst,
                            cat(ci_imm12, rd, lit(Funct3::ADD_SUB, width: 3), rd, lit(Opcode::OP_IMM, width: 7)),
                            width: 32)
          addi16sp_inst = local(:addi16sp_inst,
                                cat(addi16sp_imm12, lit(2, width: 5), lit(Funct3::ADD_SUB, width: 3), lit(2, width: 5),
                                    lit(Opcode::OP_IMM, width: 7)),
                                width: 32)
          li_inst = local(:li_inst,
                          cat(ci_imm12, lit(0, width: 5), lit(Funct3::ADD_SUB, width: 3), rd, lit(Opcode::OP_IMM, width: 7)),
                          width: 32)
          lui_inst = local(:lui_inst,
                           cat(lui_uimm20, rd, lit(Opcode::LUI, width: 7)),
                           width: 32)
          lw_inst = local(:lw_inst,
                          cat(lw_uimm12, rs1p, lit(Funct3::WORD, width: 3), rdp, lit(Opcode::LOAD, width: 7)),
                          width: 32)
          sw_inst = local(:sw_inst,
                          cat(sw_imm12[11..5], rs2p, rs1p, lit(Funct3::WORD, width: 3),
                              sw_imm12[4..0], lit(Opcode::STORE, width: 7)),
                          width: 32)
          slli_inst = local(:slli_inst,
                            cat(slli_imm12, rd, lit(Funct3::SLL, width: 3), rd, lit(Opcode::OP_IMM, width: 7)),
                            width: 32)
          srli_inst = local(:srli_inst,
                            cat(srli_imm12, rs1p, lit(Funct3::SRL_SRA, width: 3), rs1p, lit(Opcode::OP_IMM, width: 7)),
                            width: 32)
          srai_inst = local(:srai_inst,
                            cat(srai_imm12, rs1p, lit(Funct3::SRL_SRA, width: 3), rs1p, lit(Opcode::OP_IMM, width: 7)),
                            width: 32)
          andi_inst = local(:andi_inst,
                            cat(ci_imm12, rs1p, lit(Funct3::AND, width: 3), rs1p, lit(Opcode::OP_IMM, width: 7)),
                            width: 32)
          sub_inst = local(:sub_inst,
                           cat(lit(Funct7::ALT, width: 7), rs2p, rs1p, lit(Funct3::ADD_SUB, width: 3), rs1p,
                               lit(Opcode::OP, width: 7)),
                           width: 32)
          xor_inst = local(:xor_inst,
                           cat(lit(Funct7::NORMAL, width: 7), rs2p, rs1p, lit(Funct3::XOR, width: 3), rs1p,
                               lit(Opcode::OP, width: 7)),
                           width: 32)
          or_inst = local(:or_inst,
                          cat(lit(Funct7::NORMAL, width: 7), rs2p, rs1p, lit(Funct3::OR, width: 3), rs1p,
                              lit(Opcode::OP, width: 7)),
                          width: 32)
          and_inst = local(:and_inst,
                           cat(lit(Funct7::NORMAL, width: 7), rs2p, rs1p, lit(Funct3::AND, width: 3), rs1p,
                               lit(Opcode::OP, width: 7)),
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
          lwsp_inst = local(:lwsp_inst,
                            cat(lwsp_uimm12, lit(2, width: 5), lit(Funct3::WORD, width: 3), rd, lit(Opcode::LOAD, width: 7)),
                            width: 32)
          swsp_inst = local(:swsp_inst,
                            cat(swsp_imm12[11..5], rs2, lit(2, width: 5), lit(Funct3::WORD, width: 3),
                                swsp_imm12[4..0], lit(Opcode::STORE, width: 7)),
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
          rd_sp = rd == lit(2, width: 5)
          rs2_zero = rs2 == lit(0, width: 5)
          ciw_nzuimm_zero = c_inst[12..5] == lit(0, width: 8)
          ci_nzimm_zero = c_inst[12..2] == lit(0, width: 11)

          is_c_addi4spn = local(:is_c_addi4spn, is_q0 & (funct3 == lit(0b000, width: 3)) & ~ciw_nzuimm_zero, width: 1)
          is_c_addi4spn_illegal = local(:is_c_addi4spn_illegal,
                                        is_q0 & (funct3 == lit(0b000, width: 3)) & ciw_nzuimm_zero,
                                        width: 1)
          is_c_addi = local(:is_c_addi, is_q1 & (funct3 == lit(0b000, width: 3)), width: 1)
          is_c_li_illegal = local(:is_c_li_illegal, is_q1 & (funct3 == lit(0b010, width: 3)) & rd_zero, width: 1)
          is_c_li = local(:is_c_li, is_q1 & (funct3 == lit(0b010, width: 3)) & ~rd_zero, width: 1)
          is_c_addi16sp = local(:is_c_addi16sp, is_q1 & (funct3 == lit(0b011, width: 3)) & rd_sp & ~ci_nzimm_zero, width: 1)
          is_c_addi16sp_illegal = local(:is_c_addi16sp_illegal, is_q1 & (funct3 == lit(0b011, width: 3)) & rd_sp & ci_nzimm_zero, width: 1)
          is_c_lui = local(:is_c_lui, is_q1 & (funct3 == lit(0b011, width: 3)) & ~rd_zero & ~rd_sp & ~ci_nzimm_zero, width: 1)
          is_c_lui_illegal = local(:is_c_lui_illegal,
                                   is_q1 & (funct3 == lit(0b011, width: 3)) &
                                     (rd_zero | ((~rd_zero & ~rd_sp) & ci_nzimm_zero)),
                                   width: 1)
          is_c_srli = local(:is_c_srli,
                            is_q1 & (funct3 == lit(0b100, width: 3)) & (c_inst[11..10] == lit(0b00, width: 2)) &
                              (c_bit12 == lit(0, width: 1)),
                            width: 1)
          is_c_srai = local(:is_c_srai,
                            is_q1 & (funct3 == lit(0b100, width: 3)) & (c_inst[11..10] == lit(0b01, width: 2)) &
                              (c_bit12 == lit(0, width: 1)),
                            width: 1)
          is_c_andi = local(:is_c_andi,
                            is_q1 & (funct3 == lit(0b100, width: 3)) & (c_inst[11..10] == lit(0b10, width: 2)),
                            width: 1)
          is_c_sub = local(:is_c_sub,
                           is_q1 & (funct3 == lit(0b100, width: 3)) & (c_inst[11..10] == lit(0b11, width: 2)) &
                             (c_bit12 == lit(0, width: 1)) & (c_inst[6..5] == lit(0b00, width: 2)),
                           width: 1)
          is_c_xor = local(:is_c_xor,
                           is_q1 & (funct3 == lit(0b100, width: 3)) & (c_inst[11..10] == lit(0b11, width: 2)) &
                             (c_bit12 == lit(0, width: 1)) & (c_inst[6..5] == lit(0b01, width: 2)),
                           width: 1)
          is_c_or = local(:is_c_or,
                          is_q1 & (funct3 == lit(0b100, width: 3)) & (c_inst[11..10] == lit(0b11, width: 2)) &
                            (c_bit12 == lit(0, width: 1)) & (c_inst[6..5] == lit(0b10, width: 2)),
                          width: 1)
          is_c_and = local(:is_c_and,
                           is_q1 & (funct3 == lit(0b100, width: 3)) & (c_inst[11..10] == lit(0b11, width: 2)) &
                             (c_bit12 == lit(0, width: 1)) & (c_inst[6..5] == lit(0b11, width: 2)),
                           width: 1)
          is_c_shift_illegal = local(:is_c_shift_illegal,
                                     is_q1 & (funct3 == lit(0b100, width: 3)) &
                                       ((c_inst[11..10] == lit(0b00, width: 2)) | (c_inst[11..10] == lit(0b01, width: 2))) &
                                       (c_bit12 == lit(1, width: 1)),
                                     width: 1)
          is_c_alu_rv64_illegal = local(:is_c_alu_rv64_illegal,
                                        is_q1 & (funct3 == lit(0b100, width: 3)) & (c_inst[11..10] == lit(0b11, width: 2)) &
                                          (c_bit12 == lit(1, width: 1)),
                                        width: 1)
          is_c_lw = local(:is_c_lw, is_q0 & (funct3 == lit(0b010, width: 3)), width: 1)
          is_c_sw = local(:is_c_sw, is_q0 & (funct3 == lit(0b110, width: 3)), width: 1)
          is_c_j = local(:is_c_j, is_q1 & (funct3 == lit(0b101, width: 3)), width: 1)
          is_c_jal = local(:is_c_jal, is_q1 & (funct3 == lit(0b001, width: 3)), width: 1)
          is_c_beqz = local(:is_c_beqz, is_q1 & (funct3 == lit(0b110, width: 3)), width: 1)
          is_c_bnez = local(:is_c_bnez, is_q1 & (funct3 == lit(0b111, width: 3)), width: 1)
          is_c_slli = local(:is_c_slli, is_q2 & (funct3 == lit(0b000, width: 3)) & ~rd_zero & (c_bit12 == lit(0, width: 1)), width: 1)
          is_c_slli_illegal = local(:is_c_slli_illegal,
                                    is_q2 & (funct3 == lit(0b000, width: 3)) & (rd_zero | (c_bit12 == lit(1, width: 1))),
                                    width: 1)
          is_c_lwsp = local(:is_c_lwsp, is_q2 & (funct3 == lit(0b010, width: 3)) & ~rd_zero, width: 1)
          is_c_lwsp_illegal = local(:is_c_lwsp_illegal, is_q2 & (funct3 == lit(0b010, width: 3)) & rd_zero, width: 1)
          is_c_jr = local(:is_c_jr, is_q2 & (funct3 == lit(0b100, width: 3)) & (c_bit12 == lit(0, width: 1)) & rs2_zero & ~rd_zero, width: 1)
          is_c_mv = local(:is_c_mv, is_q2 & (funct3 == lit(0b100, width: 3)) & (c_bit12 == lit(0, width: 1)) & ~rs2_zero & ~rd_zero, width: 1)
          is_c_jalr = local(:is_c_jalr, is_q2 & (funct3 == lit(0b100, width: 3)) & (c_bit12 == lit(1, width: 1)) & rs2_zero & ~rd_zero, width: 1)
          is_c_add = local(:is_c_add, is_q2 & (funct3 == lit(0b100, width: 3)) & (c_bit12 == lit(1, width: 1)) & ~rs2_zero & ~rd_zero, width: 1)
          is_c_ebreak = local(:is_c_ebreak, is_q2 & (funct3 == lit(0b100, width: 3)) & (c_bit12 == lit(1, width: 1)) & rs2_zero & rd_zero, width: 1)
          is_c_swsp = local(:is_c_swsp, is_q2 & (funct3 == lit(0b110, width: 3)), width: 1)

          c_decompressed_expr = illegal_inst
          c_decompressed_expr = mux(is_c_swsp, swsp_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_lwsp, lwsp_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_ebreak, ebreak_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_add, add_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_jalr, jalr_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_mv, mv_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_jr, jr_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_slli, slli_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_bnez, bnez_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_beqz, beqz_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_jal, jal_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_j, j_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_and, and_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_or, or_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_xor, xor_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_sub, sub_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_andi, andi_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_srai, srai_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_srli, srli_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_lui, lui_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_addi16sp, addi16sp_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_sw, sw_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_lw, lw_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_li, li_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_addi, addi_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_addi4spn, addi4spn_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_slli_illegal, illegal_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_lwsp_illegal, illegal_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_shift_illegal, illegal_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_alu_rv64_illegal, illegal_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_lui_illegal, illegal_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_addi16sp_illegal, illegal_inst, c_decompressed_expr)
          c_decompressed_expr = mux(is_c_addi4spn_illegal, illegal_inst, c_decompressed_expr)
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
