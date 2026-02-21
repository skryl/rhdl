# RV32I/RV32M/RV32C Assembler
# Simple assembler for generating test programs
# Supports RV32I instructions, M extension, and a focused RV32C subset

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

    FREGISTERS = (0..31).each_with_object({}) do |index, regs|
      regs["f#{index}"] = index
    end.freeze

    VREGISTERS = (0..31).each_with_object({}) do |index, regs|
      regs["v#{index}"] = index
    end.freeze

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

    def self.fence_i
      # Zifencei: funct3=001, imm/rs1/rd are zero for canonical encoding
      encode_i_type(0, 0, 0, 0b001, Opcode::MISC_MEM)
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

    def self.sret
      # SYSTEM with imm=0x102, rd=x0, rs1=x0, funct3=000
      encode_i_type(0, 0, 0x102, 0b000, Opcode::SYSTEM)
    end

    def self.wfi
      # SYSTEM with imm=0x105, rd=x0, rs1=x0, funct3=000
      encode_i_type(0, 0, 0x105, 0b000, Opcode::SYSTEM)
    end

    def self.sfence_vma(rs1 = 0, rs2 = 0)
      # SYSTEM R-type form:
      # funct7=0001001, rs2, rs1, funct3=000, rd=x0, opcode=SYSTEM
      encode_r_type(0, rs1 & 0x1F, rs2 & 0x1F, 0b000, 0b0001001, Opcode::SYSTEM)
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

    # Floating-point loads
    def self.flw(fd, rs1, offset)
      encode_i_type(fd, rs1, offset, Funct3::WORD, Opcode::LOAD_FP)
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

    # Floating-point stores
    def self.fsw(fs2, rs1, offset)
      encode_s_type(rs1, fs2, offset, Funct3::WORD, Opcode::STORE_FP)
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

    # RV32F data-movement subset
    def self.fmv_x_w(rd, fs1)
      encode_r_type(rd, fs1, 0, 0b000, 0b1110000, Opcode::OP_FP)
    end

    def self.fmv_w_x(fd, rs1)
      encode_r_type(fd, rs1, 0, 0b000, 0b1111000, Opcode::OP_FP)
    end

    # RV32A extension (word forms)
    def self.lr_w(rd, rs1, aq: 0, rl: 0)
      encode_amo_type(rd, rs1, 0, 0b00010, aq: aq, rl: rl)
    end

    def self.sc_w(rd, rs2, rs1, aq: 0, rl: 0)
      encode_amo_type(rd, rs1, rs2, 0b00011, aq: aq, rl: rl)
    end

    def self.amoswap_w(rd, rs2, rs1, aq: 0, rl: 0)
      encode_amo_type(rd, rs1, rs2, 0b00001, aq: aq, rl: rl)
    end

    def self.amoadd_w(rd, rs2, rs1, aq: 0, rl: 0)
      encode_amo_type(rd, rs1, rs2, 0b00000, aq: aq, rl: rl)
    end

    def self.amoxor_w(rd, rs2, rs1, aq: 0, rl: 0)
      encode_amo_type(rd, rs1, rs2, 0b00100, aq: aq, rl: rl)
    end

    def self.amoand_w(rd, rs2, rs1, aq: 0, rl: 0)
      encode_amo_type(rd, rs1, rs2, 0b01100, aq: aq, rl: rl)
    end

    def self.amoor_w(rd, rs2, rs1, aq: 0, rl: 0)
      encode_amo_type(rd, rs1, rs2, 0b01000, aq: aq, rl: rl)
    end

    def self.amomin_w(rd, rs2, rs1, aq: 0, rl: 0)
      encode_amo_type(rd, rs1, rs2, 0b10000, aq: aq, rl: rl)
    end

    def self.amomax_w(rd, rs2, rs1, aq: 0, rl: 0)
      encode_amo_type(rd, rs1, rs2, 0b10100, aq: aq, rl: rl)
    end

    def self.amominu_w(rd, rs2, rs1, aq: 0, rl: 0)
      encode_amo_type(rd, rs1, rs2, 0b11000, aq: aq, rl: rl)
    end

    def self.amomaxu_w(rd, rs2, rs1, aq: 0, rl: 0)
      encode_amo_type(rd, rs1, rs2, 0b11100, aq: aq, rl: rl)
    end

    # RVV baseline subset
    # Scoped assumptions:
    # - OP-V opcode form
    # - SEW=32 baseline, LMUL=1 baseline
    # - unmasked forms only (vm=1)
    def self.vsetvli(rd, rs1, vtypei)
      imm = vtypei & 0x7FF # zimm[10:0], bit 11 must remain zero for vsetvli
      encode_i_type(rd, rs1, imm, 0b111, Opcode::OP_V)
    end

    def self.vadd_vv(vd, vs2, vs1)
      encode_v_type(vd, vs1, vs2, 0b000, 0b000000, vm: 1)
    end

    def self.vadd_vx(vd, vs2, rs1)
      encode_v_type(vd, rs1, vs2, 0b100, 0b000000, vm: 1)
    end

    def self.vmv_v_x(vd, rs1)
      # vmv.v.x is encoded in the vmerge/vmv space with vs2=0, vm=1.
      encode_v_type(vd, rs1, 0, 0b100, 0b010111, vm: 1)
    end

    def self.vmv_x_s(rd, vs2)
      # VWXUNARY0 with vs1=0 => vmv.x.s
      encode_v_type(rd, 0, vs2, 0b010, 0b010000, vm: 1)
    end

    def self.vmv_s_x(vd, rs1)
      # VRXUNARY0 with vs2=0 => vmv.s.x
      encode_v_type(vd, rs1, 0, 0b110, 0b010000, vm: 1)
    end

    # RV32C subset encoders
    # Returns [encoded_value, bit_width] tuples for use with pack_mixed.
    def self.c_raw(bits)
      [bits & 0xFFFF, 16]
    end

    def self.c_nop
      c_addi(0, 0)
    end

    def self.c_addi(rd, imm)
      c_raw(encode_c_ci(0b000, rd, imm))
    end

    def self.c_li(rd, imm)
      raise ArgumentError, 'c.li rd must be non-zero' if (rd & 0x1F).zero?

      c_raw(encode_c_ci(0b010, rd, imm))
    end

    def self.c_lw(rd, rs1, offset)
      c_raw(encode_c_lw(rs1, rd, offset))
    end

    def self.c_sw(rs2, rs1, offset)
      c_raw(encode_c_sw(rs1, rs2, offset))
    end

    def self.c_j(offset)
      c_raw(encode_c_j(0b101, offset))
    end

    def self.c_jal(offset)
      c_raw(encode_c_j(0b001, offset))
    end

    def self.c_beqz(rs1, offset)
      c_raw(encode_c_b(0b110, rs1, offset))
    end

    def self.c_bnez(rs1, offset)
      c_raw(encode_c_b(0b111, rs1, offset))
    end

    def self.c_jr(rs1)
      rs1 &= 0x1F
      raise ArgumentError, 'c.jr rs1 must be non-zero' if rs1.zero?

      c_raw((0b1000 << 12) | (rs1 << 7) | 0b10)
    end

    def self.c_jalr(rs1)
      rs1 &= 0x1F
      raise ArgumentError, 'c.jalr rs1 must be non-zero' if rs1.zero?

      c_raw((0b1001 << 12) | (rs1 << 7) | 0b10)
    end

    def self.c_mv(rd, rs2)
      rd &= 0x1F
      rs2 &= 0x1F
      raise ArgumentError, 'c.mv rd must be non-zero' if rd.zero?
      raise ArgumentError, 'c.mv rs2 must be non-zero' if rs2.zero?

      c_raw((0b1000 << 12) | (rd << 7) | (rs2 << 2) | 0b10)
    end

    def self.c_add(rd, rs2)
      rd &= 0x1F
      rs2 &= 0x1F
      raise ArgumentError, 'c.add rd must be non-zero' if rd.zero?
      raise ArgumentError, 'c.add rs2 must be non-zero' if rs2.zero?

      c_raw((0b1001 << 12) | (rd << 7) | (rs2 << 2) | 0b10)
    end

    # Packs a mixed-width instruction list into 32-bit little-endian ROM words.
    # - Integer entries are treated as 32-bit instructions
    # - [value, 16] and [value, 32] tuples are treated as explicit-width entries
    def self.pack_mixed(instructions)
      bytes = []

      instructions.each do |inst|
        value, width = normalize_mixed_entry(inst)
        case width
        when 16
          bytes << (value & 0xFF)
          bytes << ((value >> 8) & 0xFF)
        when 32
          bytes << (value & 0xFF)
          bytes << ((value >> 8) & 0xFF)
          bytes << ((value >> 16) & 0xFF)
          bytes << ((value >> 24) & 0xFF)
        else
          raise ArgumentError, "Unsupported instruction width: #{width}"
        end
      end

      words = []
      bytes.each_slice(4) do |chunk|
        padded = chunk + [0] * (4 - chunk.length)
        words << (padded[0] | (padded[1] << 8) | (padded[2] << 16) | (padded[3] << 24))
      end
      words
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
      when 'vadd.vv' then self.class.vadd_vv(vreg(args[0]), vreg(args[1]), vreg(args[2]))
      when 'vadd.vx' then self.class.vadd_vx(vreg(args[0]), vreg(args[1]), reg(args[2]))
      when 'vmv.v.x' then self.class.vmv_v_x(vreg(args[0]), reg(args[1]))
      when 'vmv.x.s' then self.class.vmv_x_s(reg(args[0]), vreg(args[1]))
      when 'vmv.s.x' then self.class.vmv_s_x(vreg(args[0]), reg(args[1]))
      when 'lr.w' then self.class.lr_w(reg(args[0]), reg(args[1]))
      when 'sc.w' then self.class.sc_w(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'amoswap.w' then self.class.amoswap_w(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'amoadd.w' then self.class.amoadd_w(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'amoxor.w' then self.class.amoxor_w(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'amoand.w' then self.class.amoand_w(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'amoor.w' then self.class.amoor_w(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'amomin.w' then self.class.amomin_w(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'amomax.w' then self.class.amomax_w(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'amominu.w' then self.class.amominu_w(reg(args[0]), reg(args[1]), reg(args[2]))
      when 'amomaxu.w' then self.class.amomaxu_w(reg(args[0]), reg(args[1]), reg(args[2]))

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
      when 'flw' then self.class.flw(freg(args[0]), reg(args[2]), imm(args[1]))

      # Store
      when 'sb' then self.class.sb(reg(args[0]), reg(args[2]), imm(args[1]))
      when 'sh' then self.class.sh(reg(args[0]), reg(args[2]), imm(args[1]))
      when 'sw' then self.class.sw(reg(args[0]), reg(args[2]), imm(args[1]))
      when 'fsw' then self.class.fsw(freg(args[0]), reg(args[2]), imm(args[1]))
      when 'fmv.x.w' then self.class.fmv_x_w(reg(args[0]), freg(args[1]))
      when 'fmv.w.x' then self.class.fmv_w_x(freg(args[0]), reg(args[1]))

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
      when 'fence.i' then self.class.fence_i
      when 'vsetvli' then self.class.vsetvli(reg(args[0]), reg(args[1]), imm(args[2]))
      when 'ecall' then self.class.ecall
      when 'ebreak' then self.class.ebreak
      when 'mret' then self.class.mret
      when 'sret' then self.class.sret
      when 'wfi' then self.class.wfi
      when 'sfence.vma' then self.class.sfence_vma(reg(args[0] || 'x0'), reg(args[1] || 'x0'))
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

    def freg(name)
      FREGISTERS[name.downcase] || raise("Unknown fp register: #{name}")
    end

    def vreg(name)
      VREGISTERS[name.downcase] || raise("Unknown vector register: #{name}")
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

    def self.encode_amo_type(rd, rs1, rs2, funct5, aq: 0, rl: 0)
      funct7 = ((funct5 & 0x1F) << 2) | ((aq & 0x1) << 1) | (rl & 0x1)
      encode_r_type(rd, rs1, rs2, Funct3::WORD, funct7, Opcode::AMO)
    end

    def self.encode_v_type(vd, rs1_or_vs1, vs2, funct3, funct6, vm: 1)
      (((funct6 & 0x3F) << 26) |
        ((vm & 0x1) << 25) |
        ((vs2 & 0x1F) << 20) |
        ((rs1_or_vs1 & 0x1F) << 15) |
        ((funct3 & 0x7) << 12) |
        ((vd & 0x1F) << 7) |
        Opcode::OP_V)
    end

    def self.normalize_mixed_entry(inst)
      if inst.is_a?(Array)
        raise ArgumentError, "Mixed-width entry must be [value, width], got: #{inst.inspect}" unless inst.length == 2

        [inst[0].to_i, inst[1].to_i]
      else
        [inst.to_i, 32]
      end
    end

    def self.encode_c_ci(funct3, rd, imm)
      rd &= 0x1F
      raise ArgumentError, "c immediate out of range: #{imm}" unless imm >= -32 && imm <= 31

      imm6 = imm & 0x3F
      ((funct3 & 0x7) << 13) |
        (((imm6 >> 5) & 0x1) << 12) |
        (rd << 7) |
        ((imm6 & 0x1F) << 2) |
        0b01
    end

    def self.encode_c_prime_reg(reg)
      reg &= 0x1F
      raise ArgumentError, 'RV32C prime register must be x8..x15' unless reg >= 8 && reg <= 15

      reg - 8
    end

    def self.encode_c_lw(rs1, rd, offset)
      raise ArgumentError, "c.lw offset must be 0..252 and 4-byte aligned: #{offset}" unless offset >= 0 && offset <= 252 && (offset & 0x3).zero?

      rs1p = encode_c_prime_reg(rs1)
      rdp = encode_c_prime_reg(rd)
      uimm = offset & 0xFF
      bit5 = (uimm >> 5) & 0x1
      bits4_2 = (uimm >> 2) & 0x7
      bit6 = (uimm >> 6) & 0x1

      (0b010 << 13) |
        (bit5 << 5) |
        (bits4_2 << 10) |
        (bit6 << 6) |
        (rs1p << 7) |
        (rdp << 2) |
        0b00
    end

    def self.encode_c_sw(rs1, rs2, offset)
      raise ArgumentError, "c.sw offset must be 0..252 and 4-byte aligned: #{offset}" unless offset >= 0 && offset <= 252 && (offset & 0x3).zero?

      rs1p = encode_c_prime_reg(rs1)
      rs2p = encode_c_prime_reg(rs2)
      uimm = offset & 0xFF
      bit5 = (uimm >> 5) & 0x1
      bits4_2 = (uimm >> 2) & 0x7
      bit6 = (uimm >> 6) & 0x1

      (0b110 << 13) |
        (bit5 << 5) |
        (bits4_2 << 10) |
        (bit6 << 6) |
        (rs1p << 7) |
        (rs2p << 2) |
        0b00
    end

    def self.encode_c_j(funct3, offset)
      raise ArgumentError, "c.j offset must be even and within [-2048, 2046]: #{offset}" unless offset.even? && offset >= -2048 && offset <= 2046

      imm = offset & 0xFFF
      b11 = (imm >> 11) & 0x1
      b10 = (imm >> 10) & 0x1
      b9 = (imm >> 9) & 0x1
      b8 = (imm >> 8) & 0x1
      b7 = (imm >> 7) & 0x1
      b6 = (imm >> 6) & 0x1
      b5 = (imm >> 5) & 0x1
      b4 = (imm >> 4) & 0x1
      b3 = (imm >> 3) & 0x1
      b2 = (imm >> 2) & 0x1
      b1 = (imm >> 1) & 0x1

      (funct3 << 13) |
        (b11 << 12) |
        (b4 << 11) |
        (b9 << 10) |
        (b8 << 9) |
        (b10 << 8) |
        (b6 << 7) |
        (b7 << 6) |
        (b3 << 5) |
        (b2 << 4) |
        (b1 << 3) |
        (b5 << 2) |
        0b01
    end

    def self.encode_c_b(funct3, rs1, offset)
      raise ArgumentError, "c branch offset must be even and within [-256, 254]: #{offset}" unless offset.even? && offset >= -256 && offset <= 254

      rs1p = encode_c_prime_reg(rs1)
      imm = offset & 0x1FF
      b8 = (imm >> 8) & 0x1
      b7 = (imm >> 7) & 0x1
      b6 = (imm >> 6) & 0x1
      b5 = (imm >> 5) & 0x1
      b4 = (imm >> 4) & 0x1
      b3 = (imm >> 3) & 0x1
      b2 = (imm >> 2) & 0x1
      b1 = (imm >> 1) & 0x1

      (funct3 << 13) |
        (b8 << 12) |
        (b4 << 11) |
        (b3 << 10) |
        (rs1p << 7) |
        (b7 << 6) |
        (b6 << 5) |
        (b2 << 4) |
        (b1 << 3) |
        (b5 << 2) |
        0b01
    end
      end
    end
  end
end
