# RV32I Instruction Decoder
# Decodes instructions and generates control signals for the datapath
# Fully synthesizable using behavior DSL

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative 'constants'

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
    output :alu_op, width: 4    # ALU operation code

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

      # Control signal generation based on opcode

      # reg_write: Write to register file for most instructions except STORE, BRANCH
      reg_write <= case_select(op, {
        Opcode::LUI    => lit(1, width: 1),
        Opcode::AUIPC  => lit(1, width: 1),
        Opcode::JAL    => lit(1, width: 1),
        Opcode::JALR   => lit(1, width: 1),
        Opcode::LOAD   => lit(1, width: 1),
        Opcode::OP_IMM => lit(1, width: 1),
        Opcode::OP     => lit(1, width: 1)
      }, default: lit(0, width: 1))

      # mem_read: Only for LOAD instructions
      mem_read <= case_select(op, {
        Opcode::LOAD => lit(1, width: 1)
      }, default: lit(0, width: 1))

      # mem_write: Only for STORE instructions
      mem_write <= case_select(op, {
        Opcode::STORE => lit(1, width: 1)
      }, default: lit(0, width: 1))

      # mem_to_reg: Select memory data for register write
      mem_to_reg <= case_select(op, {
        Opcode::LOAD => lit(1, width: 1)
      }, default: lit(0, width: 1))

      # alu_src: 0 = rs2, 1 = immediate
      # R-type uses rs2, most others use immediate
      alu_src <= case_select(op, {
        Opcode::OP     => lit(0, width: 1),
        Opcode::BRANCH => lit(0, width: 1)
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

      # Check if SUB or SRA (funct7 bit 5 set)
      is_alt = f7[5]

      # Base ALU op from funct3
      base_alu_op = case_select(f3, {
        Funct3::ADD_SUB => mux(is_alt, lit(AluOp::SUB, width: 4), lit(AluOp::ADD, width: 4)),
        Funct3::SLL     => lit(AluOp::SLL, width: 4),
        Funct3::SLT     => lit(AluOp::SLT, width: 4),
        Funct3::SLTU    => lit(AluOp::SLTU, width: 4),
        Funct3::XOR     => lit(AluOp::XOR, width: 4),
        Funct3::SRL_SRA => mux(is_alt, lit(AluOp::SRA, width: 4), lit(AluOp::SRL, width: 4)),
        Funct3::OR      => lit(AluOp::OR, width: 4),
        Funct3::AND     => lit(AluOp::AND, width: 4)
      }, default: lit(AluOp::ADD, width: 4))

      # For OP_IMM, only SRAI uses funct7 (ADDI, SLTI, etc. don't have alt ops)
      imm_alu_op = case_select(f3, {
        Funct3::ADD_SUB => lit(AluOp::ADD, width: 4),  # ADDI (no SUBI)
        Funct3::SLL     => lit(AluOp::SLL, width: 4),
        Funct3::SLT     => lit(AluOp::SLT, width: 4),
        Funct3::SLTU    => lit(AluOp::SLTU, width: 4),
        Funct3::XOR     => lit(AluOp::XOR, width: 4),
        Funct3::SRL_SRA => mux(is_alt, lit(AluOp::SRA, width: 4), lit(AluOp::SRL, width: 4)),
        Funct3::OR      => lit(AluOp::OR, width: 4),
        Funct3::AND     => lit(AluOp::AND, width: 4)
      }, default: lit(AluOp::ADD, width: 4))

      alu_op <= case_select(op, {
        Opcode::OP     => base_alu_op,
        Opcode::OP_IMM => imm_alu_op,
        Opcode::LUI    => lit(AluOp::PASS_B, width: 4),  # Pass immediate through
        Opcode::AUIPC  => lit(AluOp::ADD, width: 4),     # PC + immediate
        Opcode::JAL    => lit(AluOp::ADD, width: 4),     # Not used for result, just for address
        Opcode::JALR   => lit(AluOp::ADD, width: 4),     # rs1 + immediate
        Opcode::BRANCH => lit(AluOp::SUB, width: 4),     # Compare via subtraction
        Opcode::LOAD   => lit(AluOp::ADD, width: 4),     # rs1 + offset
        Opcode::STORE  => lit(AluOp::ADD, width: 4)      # rs1 + offset
      }, default: lit(AluOp::ADD, width: 4))

      # Instruction type for debugging
      inst_type <= case_select(op, {
        Opcode::OP     => lit(InstType::R_TYPE, width: 3),
        Opcode::OP_IMM => lit(InstType::I_TYPE, width: 3),
        Opcode::LOAD   => lit(InstType::I_TYPE, width: 3),
        Opcode::JALR   => lit(InstType::I_TYPE, width: 3),
        Opcode::STORE  => lit(InstType::S_TYPE, width: 3),
        Opcode::BRANCH => lit(InstType::B_TYPE, width: 3),
        Opcode::LUI    => lit(InstType::U_TYPE, width: 3),
        Opcode::AUIPC  => lit(InstType::U_TYPE, width: 3),
        Opcode::JAL    => lit(InstType::J_TYPE, width: 3)
      }, default: lit(InstType::R_TYPE, width: 3))
    end

  end
end
