# RV32I Instruction Decoder
# Decodes instructions and generates control signals for the datapath
# Fully synthesizable using behavior DSL

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative 'constants'

module RHDL
  module Examples
    module RISCV
      class Decoder < RHDL::HDL::Component
    include RHDL::DSL::Behavior

    input :inst, width: 32      # Full instruction

    # Decoded fields
    output :opcode, width: 7    # Opcode field
    output :rd, width: 5        # Destination register
    output :funct3, width: 3    # Function field 3
    output :rs1, width: 5       # Source register 1
    output :rs2, width: 5       # Source register 2
    output :funct7, width: 7    # Function field 7

    # Control signals
    output :reg_write           # Write to register file
    output :mem_read            # Read from memory
    output :mem_write           # Write to memory
    output :mem_to_reg          # Memory data to register
    output :alu_src             # 0=rs2, 1=immediate
    output :branch              # Branch instruction
    output :jump                # Jump instruction (JAL/JALR)
    output :jalr                # JALR (PC = rs1 + imm)
    output :alu_op, width: 6    # ALU operation code

    # Instruction type for debugging
    output :inst_type, width: 3

    behavior do
      # Extract instruction fields (always present regardless of format)
      opcode <= inst[6..0]
      rd <= inst[11..7]
      funct3 <= inst[14..12]
      rs1 <= inst[19..15]
      rs2 <= inst[24..20]
      funct7 <= inst[31..25]

      # Local extraction for control logic
      op = inst[6..0]
      f3 = inst[14..12]
      f7 = inst[31..25]
      rs2_field = inst[24..20]
      # CSR instructions are SYSTEM opcode with non-zero funct3
      is_csr = (op == lit(Opcode::SYSTEM, width: 7)) & (f3 != lit(0, width: 3))
      is_fp_mem = (f3 == lit(Funct3::WORD, width: 3)) | (f3 == lit(Funct3::DOUBLE, width: 3))
      is_fmv_x_w = (op == lit(Opcode::OP_FP, width: 7)) &
                   (f7 == lit(0b1110000, width: 7)) &
                   (rs2_field == lit(0, width: 5)) &
                   (f3 == lit(0, width: 3))
      is_fp_cmp = (op == lit(Opcode::OP_FP, width: 7)) &
                  (f7 == lit(0b1010000, width: 7))
      is_fclass = (op == lit(Opcode::OP_FP, width: 7)) &
                  (f7 == lit(0b1110000, width: 7)) &
                  (rs2_field == lit(0, width: 5)) &
                  (f3 == lit(0b001, width: 3))
      is_amo_word = (op == lit(Opcode::AMO, width: 7)) & (f3 == lit(Funct3::WORD, width: 3))
      amo_funct5 = f7[6..2]
      is_lr = is_amo_word & (amo_funct5 == lit(0b00010, width: 5)) & (rs2_field == lit(0, width: 5))
      is_sc = is_amo_word & (amo_funct5 == lit(0b00011, width: 5))
      is_amo_rmw = is_amo_word & ~is_lr & ~is_sc

      # Control signal generation based on opcode

      # reg_write: Write to register file for most instructions except STORE, BRANCH
      reg_write <= case_select(op, {
        Opcode::LUI    => lit(1, width: 1),
        Opcode::AUIPC  => lit(1, width: 1),
        Opcode::JAL    => lit(1, width: 1),
        Opcode::JALR   => lit(1, width: 1),
        Opcode::LOAD   => lit(1, width: 1),
        Opcode::OP_IMM => lit(1, width: 1),
        Opcode::OP     => lit(1, width: 1),
        Opcode::OP_FP  => is_fmv_x_w | is_fp_cmp | is_fclass,
        Opcode::AMO    => is_amo_word,
        Opcode::SYSTEM => is_csr
      }, default: lit(0, width: 1))

      # mem_read: Only for LOAD instructions
      mem_read <= case_select(op, {
        Opcode::LOAD    => lit(1, width: 1),
        Opcode::LOAD_FP => is_fp_mem,
        Opcode::AMO  => is_amo_word & ~is_sc
      }, default: lit(0, width: 1))

      # mem_write: Only for STORE instructions
      mem_write <= case_select(op, {
        Opcode::STORE    => lit(1, width: 1),
        Opcode::STORE_FP => is_fp_mem,
        Opcode::AMO   => is_amo_rmw
      }, default: lit(0, width: 1))

      # mem_to_reg: Select memory data for register write
      mem_to_reg <= case_select(op, {
        Opcode::LOAD => lit(1, width: 1),
        Opcode::AMO  => is_amo_word & ~is_sc
      }, default: lit(0, width: 1))

      # alu_src: 0 = rs2, 1 = immediate
      # R-type uses rs2, most others use immediate
      alu_src <= case_select(op, {
        Opcode::OP     => lit(0, width: 1),
        Opcode::BRANCH => lit(0, width: 1),
        Opcode::AMO    => lit(0, width: 1)
      }, default: lit(1, width: 1))

      # branch: Branch instruction - use case_select for reliable comparison
      branch <= case_select(op, {
        Opcode::BRANCH => lit(1, width: 1)
      }, default: lit(0, width: 1))

      # jump: JAL or JALR - use case_select
      jump <= case_select(op, {
        Opcode::JAL  => lit(1, width: 1),
        Opcode::JALR => lit(1, width: 1)
      }, default: lit(0, width: 1))

      # jalr: JALR specifically - use case_select
      jalr <= case_select(op, {
        Opcode::JALR => lit(1, width: 1)
      }, default: lit(0, width: 1))

      # ALU operation decode
      # For OP and OP_IMM, decode based on funct3 and funct7
      # For LUI, pass immediate through
      # For AUIPC/JAL/JALR/LOAD/STORE, use ADD
      # For BRANCH, use SUB for comparison

      # Check alternate arithmetic encoding (SUB/SRA)
      is_alt = f7[5]
      # RV32M extension uses funct7=0000001 on OP instructions
      is_m_ext = f7 == lit(Funct7::M_EXT, width: 7)
      # Zba extension (shifted-add address generation) uses funct7=0010000 on OP instructions
      is_zba_ext = f7 == lit(0b0010000, width: 7)
      # Zbb/Zbc/Zbkb subsets used in this phase
      is_zbb_logic_alt = f7 == lit(0b0100000, width: 7)
      is_zbb_minmax = f7 == lit(0b0000101, width: 7)
      is_zbkb_pack = f7 == lit(0b0000100, width: 7)

      # Base ALU op from funct3
      base_alu_op = case_select(f3, {
        Funct3::ADD_SUB => mux(is_m_ext,
                               lit(AluOp::MUL, width: 6),
                               mux(is_alt, lit(AluOp::SUB, width: 6), lit(AluOp::ADD, width: 6))),
        Funct3::SLL     => mux(is_m_ext,
                               lit(AluOp::MULH, width: 6),
                               mux(is_zbb_minmax, lit(AluOp::CLMUL, width: 6), lit(AluOp::SLL, width: 6))),
        Funct3::SLT     => mux(is_m_ext,
                               lit(AluOp::MULHSU, width: 6),
                               mux(is_zba_ext,
                                   lit(AluOp::SH1ADD, width: 6),
                                   mux(is_zbb_minmax, lit(AluOp::CLMULR, width: 6), lit(AluOp::SLT, width: 6)))),
        Funct3::SLTU    => mux(is_m_ext,
                               lit(AluOp::MULHU, width: 6),
                               mux(is_zbb_minmax, lit(AluOp::CLMULH, width: 6), lit(AluOp::SLTU, width: 6))),
        Funct3::XOR     => mux(is_m_ext,
                               lit(AluOp::DIV, width: 6),
                               mux(is_zba_ext,
                                   lit(AluOp::SH2ADD, width: 6),
                                   mux(is_zbkb_pack,
                                       lit(AluOp::PACK, width: 6),
                                       mux(is_zbb_logic_alt,
                                           lit(AluOp::XNOR, width: 6),
                                           mux(is_zbb_minmax, lit(AluOp::MIN, width: 6), lit(AluOp::XOR, width: 6)))))),
        Funct3::SRL_SRA => mux(is_m_ext,
                               lit(AluOp::DIVU, width: 6),
                               mux(is_zbb_minmax,
                                   lit(AluOp::MINU, width: 6),
                                   mux(is_alt, lit(AluOp::SRA, width: 6), lit(AluOp::SRL, width: 6)))),
        Funct3::OR      => mux(is_m_ext,
                               lit(AluOp::REM, width: 6),
                               mux(is_zba_ext,
                                   lit(AluOp::SH3ADD, width: 6),
                                   mux(is_zbb_logic_alt,
                                       lit(AluOp::ORN, width: 6),
                                       mux(is_zbb_minmax, lit(AluOp::MAX, width: 6), lit(AluOp::OR, width: 6))))),
        Funct3::AND     => mux(is_m_ext,
                               lit(AluOp::REMU, width: 6),
                               mux(is_zbkb_pack,
                                   lit(AluOp::PACKH, width: 6),
                                   mux(is_zbb_logic_alt,
                                       lit(AluOp::ANDN, width: 6),
                                       mux(is_zbb_minmax, lit(AluOp::MAXU, width: 6), lit(AluOp::AND, width: 6)))))
      }, default: lit(AluOp::ADD, width: 6))

      # For OP_IMM, only SRAI uses funct7 (ADDI, SLTI, etc. don't have alt ops)
      imm_alu_op = case_select(f3, {
        Funct3::ADD_SUB => lit(AluOp::ADD, width: 6),  # ADDI (no SUBI)
        Funct3::SLL     => lit(AluOp::SLL, width: 6),
        Funct3::SLT     => lit(AluOp::SLT, width: 6),
        Funct3::SLTU    => lit(AluOp::SLTU, width: 6),
        Funct3::XOR     => lit(AluOp::XOR, width: 6),
        Funct3::SRL_SRA => mux(is_alt, lit(AluOp::SRA, width: 6), lit(AluOp::SRL, width: 6)),
        Funct3::OR      => lit(AluOp::OR, width: 6),
        Funct3::AND     => lit(AluOp::AND, width: 6)
      }, default: lit(AluOp::ADD, width: 6))

      alu_op <= case_select(op, {
        Opcode::OP     => base_alu_op,
        Opcode::OP_IMM => imm_alu_op,
        Opcode::LUI    => lit(AluOp::PASS_B, width: 6),  # Pass immediate through
        Opcode::AUIPC  => lit(AluOp::ADD, width: 6),     # PC + immediate
        Opcode::JAL    => lit(AluOp::ADD, width: 6),     # Not used for result, just for address
        Opcode::JALR   => lit(AluOp::ADD, width: 6),     # rs1 + immediate
        Opcode::BRANCH => lit(AluOp::SUB, width: 6),     # Compare via subtraction
        Opcode::LOAD   => lit(AluOp::ADD, width: 6),     # rs1 + offset
        Opcode::STORE  => lit(AluOp::ADD, width: 6),     # rs1 + offset
        Opcode::LOAD_FP  => lit(AluOp::ADD, width: 6),   # rs1 + offset
        Opcode::STORE_FP => lit(AluOp::ADD, width: 6)    # rs1 + offset
      }, default: lit(AluOp::ADD, width: 6))

      # Instruction type for debugging
      inst_type <= case_select(op, {
        Opcode::OP     => lit(InstType::R_TYPE, width: 3),
        Opcode::OP_IMM => lit(InstType::I_TYPE, width: 3),
        Opcode::LOAD   => lit(InstType::I_TYPE, width: 3),
        Opcode::LOAD_FP => lit(InstType::I_TYPE, width: 3),
        Opcode::JALR   => lit(InstType::I_TYPE, width: 3),
        Opcode::STORE  => lit(InstType::S_TYPE, width: 3),
        Opcode::STORE_FP => lit(InstType::S_TYPE, width: 3),
        Opcode::OP_FP  => lit(InstType::R_TYPE, width: 3),
        Opcode::BRANCH => lit(InstType::B_TYPE, width: 3),
        Opcode::LUI    => lit(InstType::U_TYPE, width: 3),
        Opcode::AUIPC  => lit(InstType::U_TYPE, width: 3),
        Opcode::JAL    => lit(InstType::J_TYPE, width: 3)
      }, default: lit(InstType::R_TYPE, width: 3))
    end

      end
    end
  end
end
