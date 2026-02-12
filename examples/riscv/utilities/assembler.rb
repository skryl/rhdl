# RV32I/RV32M Assembler
# Simple assembler for generating test programs
# Supports RV32I instructions and the M extension

require_relative '../hdl/constants'

module RHDL
  module Examples
    module RISCV
      class Assembler
    # Register name mapping
    REGISTERS = {
      'x0' => 0, 'zero' => 0,
      'x1' => 1, 'ra' => 1,
      'x2' => 2, 'sp' => 2,
      'x3' => 3, 'gp' => 3,
      'x4' => 4, 'tp' => 4,
      'x5' => 5, 't0' => 5,
      'x6' => 6, 't1' => 6,
      'x7' => 7, 't2' => 7,
      'x8' => 8, 's0' => 8, 'fp' => 8,
      'x9' => 9, 's1' => 9,
      'x10' => 10, 'a0' => 10,
      'x11' => 11, 'a1' => 11,
      'x12' => 12, 'a2' => 12,
      'x13' => 13, 'a3' => 13,
      'x14' => 14, 'a4' => 14,
      'x15' => 15, 'a5' => 15,
      'x16' => 16, 'a6' => 16,
      'x17' => 17, 'a7' => 17,
      'x18' => 18, 's2' => 18,
      'x19' => 19, 's3' => 19,
      'x20' => 20, 's4' => 20,
      'x21' => 21, 's5' => 21,
      'x22' => 22, 's6' => 22,
      'x23' => 23, 's7' => 23,
      'x24' => 24, 's8' => 24,
      'x25' => 25, 's9' => 25,
      'x26' => 26, 's10' => 26,
      'x27' => 27, 's11' => 27,
      'x28' => 28, 't3' => 28,
      'x29' => 29, 't4' => 29,
      'x30' => 30, 't5' => 30,
      'x31' => 31, 't6' => 31
    }.freeze

    def initialize
      @labels = {}
      @program = []
      @current_addr = 0
    end

    # Assemble a program from text
    def assemble(source)
      lines = source.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }

      # First pass: collect labels
      addr = 0
      lines.each do |line|
        if line =~ /^(\w+):/
          @labels[$1] = addr
          line = line.sub(/^\w+:\s*/, '')
        end
        addr += 4 unless line.empty?
      end

      # Second pass: assemble instructions
      @current_addr = 0
      lines.each do |line|
        line = line.sub(/^\w+:\s*/, '')  # Remove label
        next if line.empty?

        inst = assemble_instruction(line)
        @program << inst
        @current_addr += 4
      end

      @program
    end

    # Direct instruction encoding methods
    def self.lui(rd, imm)
      encode_u_type(rd, imm, Opcode::LUI)
    end

    def self.auipc(rd, imm)
      encode_u_type(rd, imm, Opcode::AUIPC)
    end

    def self.jal(rd, offset)
      encode_j_type(rd, offset, Opcode::JAL)
    end

    def self.jalr(rd, rs1, offset)
      encode_i_type(rd, rs1, offset, 0, Opcode::JALR)
    end

    # Memory ordering / system instructions
    def self.fence(pred = 0b1111, succ = 0b1111, fm = 0)
      # I-type with rd=x0, rs1=x0, funct3=000, opcode=MISC_MEM
      # imm[11:8]=fm, imm[7:4]=pred, imm[3:0]=succ
      imm = ((fm & 0xF) << 8) | ((pred & 0xF) << 4) | (succ & 0xF)
      encode_i_type(0, 0, imm, 0b000, Opcode::MISC_MEM)
    end

    def self.ecall
      # SYSTEM with imm=0, rd=x0, rs1=x0, funct3=000
      encode_i_type(0, 0, 0, 0b000, Opcode::SYSTEM)
    end

    def self.ebreak
      # SYSTEM with imm=1, rd=x0, rs1=x0, funct3=000
      encode_i_type(0, 0, 1, 0b000, Opcode::SYSTEM)
    end

    def self.mret
      # SYSTEM with imm=0x302, rd=x0, rs1=x0, funct3=000
      encode_i_type(0, 0, 0x302, 0b000, Opcode::SYSTEM)
    end

    # Zicsr instructions
    def self.csrrw(rd, csr, rs1)
      encode_i_type(rd, rs1, csr & 0xFFF, 0b001, Opcode::SYSTEM)
    end

    def self.csrrs(rd, csr, rs1)
      encode_i_type(rd, rs1, csr & 0xFFF, 0b010, Opcode::SYSTEM)
    end

    def self.csrrc(rd, csr, rs1)
      encode_i_type(rd, rs1, csr & 0xFFF, 0b011, Opcode::SYSTEM)
    end

    def self.csrrwi(rd, csr, zimm)
      encode_i_type(rd, zimm & 0x1F, csr & 0xFFF, 0b101, Opcode::SYSTEM)
    end

    def self.csrrsi(rd, csr, zimm)
      encode_i_type(rd, zimm & 0x1F, csr & 0xFFF, 0b110, Opcode::SYSTEM)
    end

    def self.csrrci(rd, csr, zimm)
      encode_i_type(rd, zimm & 0x1F, csr & 0xFFF, 0b111, Opcode::SYSTEM)
    end

    # Branch instructions
    def self.beq(rs1, rs2, offset)
      encode_b_type(rs1, rs2, offset, Funct3::BEQ, Opcode::BRANCH)
    end

    def self.bne(rs1, rs2, offset)
      encode_b_type(rs1, rs2, offset, Funct3::BNE, Opcode::BRANCH)
    end

    def self.blt(rs1, rs2, offset)
      encode_b_type(rs1, rs2, offset, Funct3::BLT, Opcode::BRANCH)
    end

    def self.bge(rs1, rs2, offset)
      encode_b_type(rs1, rs2, offset, Funct3::BGE, Opcode::BRANCH)
    end

    def self.bltu(rs1, rs2, offset)
      encode_b_type(rs1, rs2, offset, Funct3::BLTU, Opcode::BRANCH)
    end

    def self.bgeu(rs1, rs2, offset)
      encode_b_type(rs1, rs2, offset, Funct3::BGEU, Opcode::BRANCH)
    end

    # Load instructions
    def self.lb(rd, rs1, offset)
      encode_i_type(rd, rs1, offset, Funct3::BYTE, Opcode::LOAD)
    end

    def self.lh(rd, rs1, offset)
      encode_i_type(rd, rs1, offset, Funct3::HALF, Opcode::LOAD)
    end

    def self.lw(rd, rs1, offset)
      encode_i_type(rd, rs1, offset, Funct3::WORD, Opcode::LOAD)
    end

    def self.lbu(rd, rs1, offset)
      encode_i_type(rd, rs1, offset, Funct3::BYTE_U, Opcode::LOAD)
    end

    def self.lhu(rd, rs1, offset)
      encode_i_type(rd, rs1, offset, Funct3::HALF_U, Opcode::LOAD)
    end

    # Store instructions
    def self.sb(rs2, rs1, offset)
      encode_s_type(rs1, rs2, offset, Funct3::BYTE, Opcode::STORE)
    end

    def self.sh(rs2, rs1, offset)
      encode_s_type(rs1, rs2, offset, Funct3::HALF, Opcode::STORE)
    end

    def self.sw(rs2, rs1, offset)
      encode_s_type(rs1, rs2, offset, Funct3::WORD, Opcode::STORE)
    end

    # Immediate arithmetic
    def self.addi(rd, rs1, imm)
      encode_i_type(rd, rs1, imm, Funct3::ADD_SUB, Opcode::OP_IMM)
    end

    def self.slti(rd, rs1, imm)
      encode_i_type(rd, rs1, imm, Funct3::SLT, Opcode::OP_IMM)
    end

    def self.sltiu(rd, rs1, imm)
      encode_i_type(rd, rs1, imm, Funct3::SLTU, Opcode::OP_IMM)
    end

    def self.xori(rd, rs1, imm)
      encode_i_type(rd, rs1, imm, Funct3::XOR, Opcode::OP_IMM)
    end

    def self.ori(rd, rs1, imm)
      encode_i_type(rd, rs1, imm, Funct3::OR, Opcode::OP_IMM)
    end

    def self.andi(rd, rs1, imm)
      encode_i_type(rd, rs1, imm, Funct3::AND, Opcode::OP_IMM)
    end

    def self.slli(rd, rs1, shamt)
      encode_i_type(rd, rs1, shamt & 0x1F, Funct3::SLL, Opcode::OP_IMM)
    end

    def self.srli(rd, rs1, shamt)
      encode_i_type(rd, rs1, shamt & 0x1F, Funct3::SRL_SRA, Opcode::OP_IMM)
    end

    def self.srai(rd, rs1, shamt)
      encode_i_type(rd, rs1, (shamt & 0x1F) | 0x400, Funct3::SRL_SRA, Opcode::OP_IMM)
    end

    # Register-register arithmetic
    def self.add(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::ADD_SUB, Funct7::NORMAL, Opcode::OP)
    end

    def self.sub(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::ADD_SUB, Funct7::ALT, Opcode::OP)
    end

    def self.sll(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::SLL, Funct7::NORMAL, Opcode::OP)
    end

    def self.slt(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::SLT, Funct7::NORMAL, Opcode::OP)
    end

    def self.sltu(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::SLTU, Funct7::NORMAL, Opcode::OP)
    end

    def self.xor(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::XOR, Funct7::NORMAL, Opcode::OP)
    end

    def self.srl(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::SRL_SRA, Funct7::NORMAL, Opcode::OP)
    end

    def self.sra(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::SRL_SRA, Funct7::ALT, Opcode::OP)
    end

    def self.or(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::OR, Funct7::NORMAL, Opcode::OP)
    end

    def self.and(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::AND, Funct7::NORMAL, Opcode::OP)
    end

    # RV32M extension
    def self.mul(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::ADD_SUB, Funct7::M_EXT, Opcode::OP)
    end

    def self.mulh(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::SLL, Funct7::M_EXT, Opcode::OP)
    end

    def self.mulhsu(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::SLT, Funct7::M_EXT, Opcode::OP)
    end

    def self.mulhu(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::SLTU, Funct7::M_EXT, Opcode::OP)
    end

    def self.div(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::XOR, Funct7::M_EXT, Opcode::OP)
    end

    def self.divu(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::SRL_SRA, Funct7::M_EXT, Opcode::OP)
    end

    def self.rem(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::OR, Funct7::M_EXT, Opcode::OP)
    end

    def self.remu(rd, rs1, rs2)
      encode_r_type(rd, rs1, rs2, Funct3::AND, Funct7::M_EXT, Opcode::OP)
    end

    # Aliases for Ruby reserved words
    class << self
      alias_method :and_inst, :and
      alias_method :or_inst, :or
      alias_method :xor_inst, :xor
    end

    # Pseudo-instructions
    def self.nop
      addi(0, 0, 0)
    end

    def self.li(rd, imm)
      # Load immediate (simplified - just uses addi for small values)
      if imm >= -2048 && imm < 2048
        addi(rd, 0, imm)
      else
        # For larger values, use lui + addi
        upper = (imm + 0x800) >> 12
        lower = imm - (upper << 12)
        [lui(rd, upper), addi(rd, rd, lower)]
      end
    end

    def self.mv(rd, rs)
      addi(rd, rs, 0)
    end

    def self.not(rd, rs)
      xori(rd, rs, -1)
    end

    def self.neg(rd, rs)
      sub(rd, 0, rs)
    end

    def self.seqz(rd, rs)
      sltiu(rd, rs, 1)
    end

    def self.snez(rd, rs)
      sltu(rd, 0, rs)
    end

    def self.j(offset)
      jal(0, offset)
    end

    def self.jr(rs)
      jalr(0, rs, 0)
    end

    def self.ret
      jalr(0, 1, 0)  # jalr x0, ra, 0
    end

    private

    def assemble_instruction(line)
      parts = line.split(/[,\s()]+/).reject(&:empty?)
      mnemonic = parts[0].downcase
      args = parts[1..]

      case mnemonic
      # R-type
      when 'add' then self.class.add(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'sub' then self.class.sub(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'sll' then self.class.sll(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'slt' then self.class.slt(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'sltu' then self.class.sltu(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'xor' then self.class.xor(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'srl' then self.class.srl(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'sra' then self.class.sra(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'or' then self.class.or(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'and' then self.class.and(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'mul' then self.class.mul(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'mulh' then self.class.mulh(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'mulhsu' then self.class.mulhsu(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'mulhu' then self.class.mulhu(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'div' then self.class.div(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'divu' then self.class.divu(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'rem' then self.class.rem(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'remu' then self.class.remu(reg(args[0]), reg(args[1]), reg(args[2]))

      # I-type arithmetic
      when 'addi' then self.class.addi(reg(args[0]), reg(args[1]), imm(args[2]))
      when 'slti' then self.class.slti(reg(args[0]), reg(args[1]), imm(args[2]))
      when 'sltiu' then self.class.sltiu(reg(args[0]), reg(args[1]), imm(args[2]))
      when 'xori' then self.class.xori(reg(args[0]), reg(args[1]), imm(args[2]))
      when 'ori' then self.class.ori(reg(args[0]), reg(args[1]), imm(args[2]))
      when 'andi' then self.class.andi(reg(args[0]), reg(args[1]), imm(args[2]))
      when 'slli' then self.class.slli(reg(args[0]), reg(args[1]), imm(args[2]))
      when 'srli' then self.class.srli(reg(args[0]), reg(args[1]), imm(args[2]))
      when 'srai' then self.class.srai(reg(args[0]), reg(args[1]), imm(args[2]))

      # Load
      when 'lb' then self.class.lb(reg(args[0]), reg(args[2]), imm(args[1]))
      when 'lh' then self.class.lh(reg(args[0]), reg(args[2]), imm(args[1]))
      when 'lw' then self.class.lw(reg(args[0]), reg(args[2]), imm(args[1]))
      when 'lbu' then self.class.lbu(reg(args[0]), reg(args[2]), imm(args[1]))
      when 'lhu' then self.class.lhu(reg(args[0]), reg(args[2]), imm(args[1]))

      # Store
      when 'sb' then self.class.sb(reg(args[0]), reg(args[2]), imm(args[1]))
      when 'sh' then self.class.sh(reg(args[0]), reg(args[2]), imm(args[1]))
      when 'sw' then self.class.sw(reg(args[0]), reg(args[2]), imm(args[1]))

      # Branch
      when 'beq' then self.class.beq(reg(args[0]), reg(args[1]), label_offset(args[2]))
      when 'bne' then self.class.bne(reg(args[0]), reg(args[1]), label_offset(args[2]))
      when 'blt' then self.class.blt(reg(args[0]), reg(args[1]), label_offset(args[2]))
      when 'bge' then self.class.bge(reg(args[0]), reg(args[1]), label_offset(args[2]))
      when 'bltu' then self.class.bltu(reg(args[0]), reg(args[1]), label_offset(args[2]))
      when 'bgeu' then self.class.bgeu(reg(args[0]), reg(args[1]), label_offset(args[2]))

      # Jump
      when 'jal' then self.class.jal(reg(args[0]), label_offset(args[1]))
      when 'jalr' then self.class.jalr(reg(args[0]), reg(args[1]), imm(args[2]))

      # System / memory-ordering
      when 'fence' then self.class.fence
      when 'ecall' then self.class.ecall
      when 'ebreak' then self.class.ebreak
      when 'mret' then self.class.mret
      when 'csrrw' then self.class.csrrw(reg(args[0]), imm(args[1]), reg(args[2]))
      when 'csrrs' then self.class.csrrs(reg(args[0]), imm(args[1]), reg(args[2]))
      when 'csrrc' then self.class.csrrc(reg(args[0]), imm(args[1]), reg(args[2]))
      when 'csrrwi' then self.class.csrrwi(reg(args[0]), imm(args[1]), imm(args[2]))
      when 'csrrsi' then self.class.csrrsi(reg(args[0]), imm(args[1]), imm(args[2]))
      when 'csrrci' then self.class.csrrci(reg(args[0]), imm(args[1]), imm(args[2]))

      # U-type
      when 'lui' then self.class.lui(reg(args[0]), imm(args[1]))
      when 'auipc' then self.class.auipc(reg(args[0]), imm(args[1]))

      # Pseudo-instructions
      when 'nop' then self.class.nop
      when 'li'
        li_result = self.class.li(reg(args[0]), imm(args[1]))
        if li_result.is_a?(Array)
          # Handle two-instruction li
          @program << li_result[0]
          @current_addr += 4
          li_result[1]
        else
          li_result
        end
      when 'mv' then self.class.mv(reg(args[0]), reg(args[1]))
      when 'not' then self.class.not(reg(args[0]), reg(args[1]))
      when 'neg' then self.class.neg(reg(args[0]), reg(args[1]))
      when 'j' then self.class.j(label_offset(args[0]))
      when 'jr' then self.class.jr(reg(args[0]))
      when 'ret' then self.class.ret

      else
        raise "Unknown instruction: #{mnemonic}"
      end
    end

    def reg(name)
      REGISTERS[name.downcase] || raise("Unknown register: #{name}")
    end

    def imm(value)
      if value =~ /^-?\d+$/
        value.to_i
      elsif value =~ /^0x[0-9a-fA-F]+$/
        value.to_i(16)
      else
        raise "Invalid immediate: #{value}"
      end
    end

    def label_offset(name)
      if name =~ /^-?\d+$/
        name.to_i
      elsif @labels[name]
        @labels[name] - @current_addr
      else
        raise "Unknown label: #{name}"
      end
    end

    # Encoding helpers (class methods)
    def self.encode_r_type(rd, rs1, rs2, funct3, funct7, opcode)
      (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
    end

    def self.encode_i_type(rd, rs1, imm, funct3, opcode)
      ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
    end

    def self.encode_s_type(rs1, rs2, imm, funct3, opcode)
      imm_11_5 = (imm >> 5) & 0x7F
      imm_4_0 = imm & 0x1F
      (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | opcode
    end

    def self.encode_b_type(rs1, rs2, imm, funct3, opcode)
      # B-type immediate encoding: imm[12|10:5|4:1|11]
      imm_12 = (imm >> 12) & 0x1
      imm_10_5 = (imm >> 5) & 0x3F
      imm_4_1 = (imm >> 1) & 0xF
      imm_11 = (imm >> 11) & 0x1
      (imm_12 << 31) | (imm_10_5 << 25) | (rs2 << 20) | (rs1 << 15) |
        (funct3 << 12) | (imm_4_1 << 8) | (imm_11 << 7) | opcode
    end

    def self.encode_u_type(rd, imm, opcode)
      ((imm & 0xFFFFF) << 12) | (rd << 7) | opcode
    end

    def self.encode_j_type(rd, imm, opcode)
      # J-type immediate encoding: imm[20|10:1|11|19:12]
      imm_20 = (imm >> 20) & 0x1
      imm_10_1 = (imm >> 1) & 0x3FF
      imm_11 = (imm >> 11) & 0x1
      imm_19_12 = (imm >> 12) & 0xFF
      (imm_20 << 31) | (imm_10_1 << 21) | (imm_11 << 20) | (imm_19_12 << 12) | (rd << 7) | opcode
    end
      end
    end
  end
end
