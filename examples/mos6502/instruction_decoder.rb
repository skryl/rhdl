# MOS 6502 Instruction Decoder
# Decodes opcodes into control signals

module MOS6502
  class InstructionDecoder < RHDL::HDL::SimComponent
    # Instruction types
    TYPE_ALU       = 0x00  # ALU operations (ADC, SBC, AND, ORA, EOR, CMP, BIT)
    TYPE_LOAD      = 0x01  # Load register (LDA, LDX, LDY)
    TYPE_STORE     = 0x02  # Store register (STA, STX, STY)
    TYPE_TRANSFER  = 0x03  # Register transfer (TAX, TXA, etc.)
    TYPE_INC_DEC   = 0x04  # Increment/Decrement (INC, DEC, INX, INY, DEX, DEY)
    TYPE_SHIFT     = 0x05  # Shift/Rotate (ASL, LSR, ROL, ROR)
    TYPE_BRANCH    = 0x06  # Conditional branch
    TYPE_JUMP      = 0x07  # Unconditional jump (JMP, JSR, RTS, RTI)
    TYPE_STACK     = 0x08  # Stack operations (PHA, PHP, PLA, PLP)
    TYPE_FLAG      = 0x09  # Flag operations (CLC, SEC, etc.)
    TYPE_NOP       = 0x0A  # No operation
    TYPE_BRK       = 0x0B  # Break

    # Branch condition types
    BRANCH_BPL = 0  # Branch on Plus (N=0)
    BRANCH_BMI = 1  # Branch on Minus (N=1)
    BRANCH_BVC = 2  # Branch on Overflow Clear (V=0)
    BRANCH_BVS = 3  # Branch on Overflow Set (V=1)
    BRANCH_BCC = 4  # Branch on Carry Clear (C=0)
    BRANCH_BCS = 5  # Branch on Carry Set (C=1)
    BRANCH_BNE = 6  # Branch on Not Equal (Z=0)
    BRANCH_BEQ = 7  # Branch on Equal (Z=1)

    def initialize(name = nil)
      super(name)
      build_decode_table
    end

    def setup_ports
      input :opcode, width: 8

      # Decoded outputs
      output :addr_mode, width: 4      # Addressing mode
      output :alu_op, width: 4         # ALU operation
      output :instr_type, width: 4     # Instruction type
      output :src_reg, width: 2        # Source register (0=A, 1=X, 2=Y)
      output :dst_reg, width: 2        # Destination register
      output :branch_cond, width: 3    # Branch condition
      output :cycles_base, width: 3    # Base cycle count
      output :is_read                  # Reads from memory
      output :is_write                 # Writes to memory
      output :is_rmw                   # Read-Modify-Write operation
      output :sets_nz                  # Sets N and Z flags
      output :sets_c                   # Sets carry flag
      output :sets_v                   # Sets overflow flag
      output :writes_reg               # Writes to a register
      output :illegal                  # Illegal/undefined opcode
    end

    def propagate
      opcode = in_val(:opcode) & 0xFF
      info = @decode_table[opcode] || illegal_opcode

      out_set(:addr_mode, info[:addr_mode])
      out_set(:alu_op, info[:alu_op])
      out_set(:instr_type, info[:type])
      out_set(:src_reg, info[:src_reg])
      out_set(:dst_reg, info[:dst_reg])
      out_set(:branch_cond, info[:branch_cond])
      out_set(:cycles_base, info[:cycles])
      out_set(:is_read, info[:is_read])
      out_set(:is_write, info[:is_write])
      out_set(:is_rmw, info[:is_rmw])
      out_set(:sets_nz, info[:sets_nz])
      out_set(:sets_c, info[:sets_c])
      out_set(:sets_v, info[:sets_v])
      out_set(:writes_reg, info[:writes_reg] || 0)
      out_set(:illegal, info[:illegal])
    end

    private

    def illegal_opcode
      {
        addr_mode: AddressGenerator::MODE_IMPLIED,
        alu_op: ALU::OP_NOP,
        type: TYPE_NOP,
        src_reg: REG_A,
        dst_reg: REG_A,
        branch_cond: 0,
        cycles: 2,
        is_read: 0,
        is_write: 0,
        is_rmw: 0,
        sets_nz: 0,
        sets_c: 0,
        sets_v: 0,
        illegal: 1
      }
    end

    def build_decode_table
      @decode_table = {}

      # Convenience for building entries
      implied = AddressGenerator::MODE_IMPLIED
      accum = AddressGenerator::MODE_ACCUMULATOR
      imm = AddressGenerator::MODE_IMMEDIATE
      zp = AddressGenerator::MODE_ZERO_PAGE
      zpx = AddressGenerator::MODE_ZERO_PAGE_X
      zpy = AddressGenerator::MODE_ZERO_PAGE_Y
      abs = AddressGenerator::MODE_ABSOLUTE
      absx = AddressGenerator::MODE_ABSOLUTE_X
      absy = AddressGenerator::MODE_ABSOLUTE_Y
      ind = AddressGenerator::MODE_INDIRECT
      indx = AddressGenerator::MODE_INDEXED_IND
      indy = AddressGenerator::MODE_INDIRECT_IDX
      rel = AddressGenerator::MODE_RELATIVE

      # === ADC - Add with Carry ===
      add_alu(:ADC, 0x69, imm,  ALU::OP_ADC, 2)
      add_alu(:ADC, 0x65, zp,   ALU::OP_ADC, 3)
      add_alu(:ADC, 0x75, zpx,  ALU::OP_ADC, 4)
      add_alu(:ADC, 0x6D, abs,  ALU::OP_ADC, 4)
      add_alu(:ADC, 0x7D, absx, ALU::OP_ADC, 4)
      add_alu(:ADC, 0x79, absy, ALU::OP_ADC, 4)
      add_alu(:ADC, 0x61, indx, ALU::OP_ADC, 6)
      add_alu(:ADC, 0x71, indy, ALU::OP_ADC, 5)

      # === SBC - Subtract with Carry ===
      add_alu(:SBC, 0xE9, imm,  ALU::OP_SBC, 2)
      add_alu(:SBC, 0xE5, zp,   ALU::OP_SBC, 3)
      add_alu(:SBC, 0xF5, zpx,  ALU::OP_SBC, 4)
      add_alu(:SBC, 0xED, abs,  ALU::OP_SBC, 4)
      add_alu(:SBC, 0xFD, absx, ALU::OP_SBC, 4)
      add_alu(:SBC, 0xF9, absy, ALU::OP_SBC, 4)
      add_alu(:SBC, 0xE1, indx, ALU::OP_SBC, 6)
      add_alu(:SBC, 0xF1, indy, ALU::OP_SBC, 5)

      # === AND - Logical AND ===
      add_alu(:AND, 0x29, imm,  ALU::OP_AND, 2)
      add_alu(:AND, 0x25, zp,   ALU::OP_AND, 3)
      add_alu(:AND, 0x35, zpx,  ALU::OP_AND, 4)
      add_alu(:AND, 0x2D, abs,  ALU::OP_AND, 4)
      add_alu(:AND, 0x3D, absx, ALU::OP_AND, 4)
      add_alu(:AND, 0x39, absy, ALU::OP_AND, 4)
      add_alu(:AND, 0x21, indx, ALU::OP_AND, 6)
      add_alu(:AND, 0x31, indy, ALU::OP_AND, 5)

      # === ORA - Logical OR ===
      add_alu(:ORA, 0x09, imm,  ALU::OP_ORA, 2)
      add_alu(:ORA, 0x05, zp,   ALU::OP_ORA, 3)
      add_alu(:ORA, 0x15, zpx,  ALU::OP_ORA, 4)
      add_alu(:ORA, 0x0D, abs,  ALU::OP_ORA, 4)
      add_alu(:ORA, 0x1D, absx, ALU::OP_ORA, 4)
      add_alu(:ORA, 0x19, absy, ALU::OP_ORA, 4)
      add_alu(:ORA, 0x01, indx, ALU::OP_ORA, 6)
      add_alu(:ORA, 0x11, indy, ALU::OP_ORA, 5)

      # === EOR - Logical XOR ===
      add_alu(:EOR, 0x49, imm,  ALU::OP_EOR, 2)
      add_alu(:EOR, 0x45, zp,   ALU::OP_EOR, 3)
      add_alu(:EOR, 0x55, zpx,  ALU::OP_EOR, 4)
      add_alu(:EOR, 0x4D, abs,  ALU::OP_EOR, 4)
      add_alu(:EOR, 0x5D, absx, ALU::OP_EOR, 4)
      add_alu(:EOR, 0x59, absy, ALU::OP_EOR, 4)
      add_alu(:EOR, 0x41, indx, ALU::OP_EOR, 6)
      add_alu(:EOR, 0x51, indy, ALU::OP_EOR, 5)

      # === CMP - Compare Accumulator ===
      add_cmp(:CMP, 0xC9, imm,  REG_A, 2)
      add_cmp(:CMP, 0xC5, zp,   REG_A, 3)
      add_cmp(:CMP, 0xD5, zpx,  REG_A, 4)
      add_cmp(:CMP, 0xCD, abs,  REG_A, 4)
      add_cmp(:CMP, 0xDD, absx, REG_A, 4)
      add_cmp(:CMP, 0xD9, absy, REG_A, 4)
      add_cmp(:CMP, 0xC1, indx, REG_A, 6)
      add_cmp(:CMP, 0xD1, indy, REG_A, 5)

      # === CPX - Compare X ===
      add_cmp(:CPX, 0xE0, imm, REG_X, 2)
      add_cmp(:CPX, 0xE4, zp,  REG_X, 3)
      add_cmp(:CPX, 0xEC, abs, REG_X, 4)

      # === CPY - Compare Y ===
      add_cmp(:CPY, 0xC0, imm, REG_Y, 2)
      add_cmp(:CPY, 0xC4, zp,  REG_Y, 3)
      add_cmp(:CPY, 0xCC, abs, REG_Y, 4)

      # === BIT - Bit Test ===
      add_bit(0x24, zp,  3)
      add_bit(0x2C, abs, 4)

      # === LDA - Load Accumulator ===
      add_load(:LDA, 0xA9, imm,  REG_A, 2)
      add_load(:LDA, 0xA5, zp,   REG_A, 3)
      add_load(:LDA, 0xB5, zpx,  REG_A, 4)
      add_load(:LDA, 0xAD, abs,  REG_A, 4)
      add_load(:LDA, 0xBD, absx, REG_A, 4)
      add_load(:LDA, 0xB9, absy, REG_A, 4)
      add_load(:LDA, 0xA1, indx, REG_A, 6)
      add_load(:LDA, 0xB1, indy, REG_A, 5)

      # === LDX - Load X ===
      add_load(:LDX, 0xA2, imm,  REG_X, 2)
      add_load(:LDX, 0xA6, zp,   REG_X, 3)
      add_load(:LDX, 0xB6, zpy,  REG_X, 4)
      add_load(:LDX, 0xAE, abs,  REG_X, 4)
      add_load(:LDX, 0xBE, absy, REG_X, 4)

      # === LDY - Load Y ===
      add_load(:LDY, 0xA0, imm,  REG_Y, 2)
      add_load(:LDY, 0xA4, zp,   REG_Y, 3)
      add_load(:LDY, 0xB4, zpx,  REG_Y, 4)
      add_load(:LDY, 0xAC, abs,  REG_Y, 4)
      add_load(:LDY, 0xBC, absx, REG_Y, 4)

      # === STA - Store Accumulator ===
      add_store(:STA, 0x85, zp,   REG_A, 3)
      add_store(:STA, 0x95, zpx,  REG_A, 4)
      add_store(:STA, 0x8D, abs,  REG_A, 4)
      add_store(:STA, 0x9D, absx, REG_A, 5)
      add_store(:STA, 0x99, absy, REG_A, 5)
      add_store(:STA, 0x81, indx, REG_A, 6)
      add_store(:STA, 0x91, indy, REG_A, 6)

      # === STX - Store X ===
      add_store(:STX, 0x86, zp,  REG_X, 3)
      add_store(:STX, 0x96, zpy, REG_X, 4)
      add_store(:STX, 0x8E, abs, REG_X, 4)

      # === STY - Store Y ===
      add_store(:STY, 0x84, zp,  REG_Y, 3)
      add_store(:STY, 0x94, zpx, REG_Y, 4)
      add_store(:STY, 0x8C, abs, REG_Y, 4)

      # === Register Transfers ===
      add_transfer(0xAA, REG_A, REG_X, :TAX)  # TAX
      add_transfer(0x8A, REG_X, REG_A, :TXA)  # TXA
      add_transfer(0xA8, REG_A, REG_Y, :TAY)  # TAY
      add_transfer(0x98, REG_Y, REG_A, :TYA)  # TYA
      add_transfer(0xBA, REG_X, REG_X, :TSX)  # TSX (special: S -> X)
      add_transfer(0x9A, REG_X, REG_X, :TXS)  # TXS (special: X -> S)

      # === Increment/Decrement Register ===
      add_inc_dec_reg(0xE8, REG_X, true,  :INX)   # INX
      add_inc_dec_reg(0xCA, REG_X, false, :DEX)   # DEX
      add_inc_dec_reg(0xC8, REG_Y, true,  :INY)   # INY
      add_inc_dec_reg(0x88, REG_Y, false, :DEY)   # DEY

      # === Increment/Decrement Memory ===
      add_inc_dec_mem(0xE6, zp,   true,  :INC, 5)  # INC zp
      add_inc_dec_mem(0xF6, zpx,  true,  :INC, 6)  # INC zp,X
      add_inc_dec_mem(0xEE, abs,  true,  :INC, 6)  # INC abs
      add_inc_dec_mem(0xFE, absx, true,  :INC, 7)  # INC abs,X
      add_inc_dec_mem(0xC6, zp,   false, :DEC, 5)  # DEC zp
      add_inc_dec_mem(0xD6, zpx,  false, :DEC, 6)  # DEC zp,X
      add_inc_dec_mem(0xCE, abs,  false, :DEC, 6)  # DEC abs
      add_inc_dec_mem(0xDE, absx, false, :DEC, 7)  # DEC abs,X

      # === Shift/Rotate ===
      # ASL - Arithmetic Shift Left
      add_shift(0x0A, accum, ALU::OP_ASL, 2)
      add_shift(0x06, zp,    ALU::OP_ASL, 5)
      add_shift(0x16, zpx,   ALU::OP_ASL, 6)
      add_shift(0x0E, abs,   ALU::OP_ASL, 6)
      add_shift(0x1E, absx,  ALU::OP_ASL, 7)

      # LSR - Logical Shift Right
      add_shift(0x4A, accum, ALU::OP_LSR, 2)
      add_shift(0x46, zp,    ALU::OP_LSR, 5)
      add_shift(0x56, zpx,   ALU::OP_LSR, 6)
      add_shift(0x4E, abs,   ALU::OP_LSR, 6)
      add_shift(0x5E, absx,  ALU::OP_LSR, 7)

      # ROL - Rotate Left
      add_shift(0x2A, accum, ALU::OP_ROL, 2)
      add_shift(0x26, zp,    ALU::OP_ROL, 5)
      add_shift(0x36, zpx,   ALU::OP_ROL, 6)
      add_shift(0x2E, abs,   ALU::OP_ROL, 6)
      add_shift(0x3E, absx,  ALU::OP_ROL, 7)

      # ROR - Rotate Right
      add_shift(0x6A, accum, ALU::OP_ROR, 2)
      add_shift(0x66, zp,    ALU::OP_ROR, 5)
      add_shift(0x76, zpx,   ALU::OP_ROR, 6)
      add_shift(0x6E, abs,   ALU::OP_ROR, 6)
      add_shift(0x7E, absx,  ALU::OP_ROR, 7)

      # === Branches ===
      add_branch(0x10, BRANCH_BPL)  # BPL
      add_branch(0x30, BRANCH_BMI)  # BMI
      add_branch(0x50, BRANCH_BVC)  # BVC
      add_branch(0x70, BRANCH_BVS)  # BVS
      add_branch(0x90, BRANCH_BCC)  # BCC
      add_branch(0xB0, BRANCH_BCS)  # BCS
      add_branch(0xD0, BRANCH_BNE)  # BNE
      add_branch(0xF0, BRANCH_BEQ)  # BEQ

      # === Jumps ===
      add_jump(0x4C, abs, :JMP, 3)   # JMP absolute
      add_jump(0x6C, ind, :JMP, 5)   # JMP indirect
      add_jump(0x20, abs, :JSR, 6)   # JSR
      add_jump(0x60, implied, :RTS, 6)  # RTS
      add_jump(0x40, implied, :RTI, 6)  # RTI

      # === Stack Operations ===
      add_stack(0x48, :PHA, true,  false)  # PHA
      add_stack(0x08, :PHP, true,  true)   # PHP
      add_stack(0x68, :PLA, false, false)  # PLA
      add_stack(0x28, :PLP, false, true)   # PLP

      # === Flag Operations ===
      add_flag(0x18, :CLC, :c, 0)  # CLC
      add_flag(0x38, :SEC, :c, 1)  # SEC
      add_flag(0x58, :CLI, :i, 0)  # CLI
      add_flag(0x78, :SEI, :i, 1)  # SEI
      add_flag(0xB8, :CLV, :v, 0)  # CLV
      add_flag(0xD8, :CLD, :d, 0)  # CLD
      add_flag(0xF8, :SED, :d, 1)  # SED

      # === NOP ===
      @decode_table[0xEA] = {
        addr_mode: implied,
        alu_op: ALU::OP_NOP,
        type: TYPE_NOP,
        src_reg: REG_A,
        dst_reg: REG_A,
        branch_cond: 0,
        cycles: 2,
        is_read: 0,
        is_write: 0,
        is_rmw: 0,
        sets_nz: 0,
        sets_c: 0,
        sets_v: 0,
        illegal: 0
      }

      # === BRK ===
      @decode_table[0x00] = {
        addr_mode: implied,
        alu_op: ALU::OP_NOP,
        type: TYPE_BRK,
        src_reg: REG_A,
        dst_reg: REG_A,
        branch_cond: 0,
        cycles: 7,
        is_read: 0,
        is_write: 0,
        is_rmw: 0,
        sets_nz: 0,
        sets_c: 0,
        sets_v: 0,
        illegal: 0
      }
    end

    # Helper methods for adding opcodes to decode table
    def add_alu(name, opcode, mode, alu_op, cycles)
      @decode_table[opcode] = {
        addr_mode: mode,
        alu_op: alu_op,
        type: TYPE_ALU,
        src_reg: REG_A,
        dst_reg: REG_A,
        branch_cond: 0,
        cycles: cycles,
        is_read: (mode == AddressGenerator::MODE_IMMEDIATE) ? 0 : 1,
        is_write: 0,
        is_rmw: 0,
        sets_nz: 1,
        sets_c: (alu_op == ALU::OP_ADC || alu_op == ALU::OP_SBC) ? 1 : 0,
        sets_v: (alu_op == ALU::OP_ADC || alu_op == ALU::OP_SBC) ? 1 : 0,
        writes_reg: 1,  # ALU ops (ADC, SBC, AND, ORA, EOR) write to A
        illegal: 0
      }
    end

    def add_cmp(name, opcode, mode, reg, cycles)
      @decode_table[opcode] = {
        addr_mode: mode,
        alu_op: ALU::OP_CMP,
        type: TYPE_ALU,
        src_reg: reg,
        dst_reg: reg,
        branch_cond: 0,
        cycles: cycles,
        is_read: (mode == AddressGenerator::MODE_IMMEDIATE) ? 0 : 1,
        is_write: 0,
        is_rmw: 0,
        sets_nz: 1,
        sets_c: 1,
        sets_v: 0,
        writes_reg: 0,  # CMP doesn't write to registers
        illegal: 0
      }
    end

    def add_bit(opcode, mode, cycles)
      @decode_table[opcode] = {
        addr_mode: mode,
        alu_op: ALU::OP_BIT,
        type: TYPE_ALU,
        src_reg: REG_A,
        dst_reg: REG_A,
        branch_cond: 0,
        cycles: cycles,
        is_read: 1,
        is_write: 0,
        is_rmw: 0,
        sets_nz: 1,  # Actually sets N, Z, and V
        sets_c: 0,
        sets_v: 1,
        writes_reg: 0,  # BIT doesn't write to registers
        illegal: 0
      }
    end

    def add_load(name, opcode, mode, reg, cycles)
      @decode_table[opcode] = {
        addr_mode: mode,
        alu_op: ALU::OP_TST,
        type: TYPE_LOAD,
        src_reg: reg,
        dst_reg: reg,
        branch_cond: 0,
        cycles: cycles,
        is_read: (mode == AddressGenerator::MODE_IMMEDIATE) ? 0 : 1,
        is_write: 0,
        is_rmw: 0,
        sets_nz: 1,
        sets_c: 0,
        sets_v: 0,
        writes_reg: 1,  # Load writes to register
        illegal: 0
      }
    end

    def add_store(name, opcode, mode, reg, cycles)
      @decode_table[opcode] = {
        addr_mode: mode,
        alu_op: ALU::OP_NOP,
        type: TYPE_STORE,
        src_reg: reg,
        dst_reg: reg,
        branch_cond: 0,
        cycles: cycles,
        is_read: 0,
        is_write: 1,
        is_rmw: 0,
        sets_nz: 0,
        sets_c: 0,
        sets_v: 0,
        illegal: 0
      }
    end

    def add_transfer(opcode, src, dst, name)
      @decode_table[opcode] = {
        addr_mode: AddressGenerator::MODE_IMPLIED,
        alu_op: ALU::OP_TST,
        type: TYPE_TRANSFER,
        src_reg: src,
        dst_reg: dst,
        branch_cond: 0,
        cycles: 2,
        is_read: 0,
        is_write: 0,
        is_rmw: 0,
        sets_nz: (name == :TXS) ? 0 : 1,  # TXS doesn't affect flags
        sets_c: 0,
        sets_v: 0,
        writes_reg: (name == :TXS) ? 0 : 1,  # TXS writes to stack pointer, not register
        illegal: 0,
        mnemonic: name
      }
    end

    def add_inc_dec_reg(opcode, reg, is_inc, name)
      @decode_table[opcode] = {
        addr_mode: AddressGenerator::MODE_IMPLIED,
        alu_op: is_inc ? ALU::OP_INC : ALU::OP_DEC,
        type: TYPE_INC_DEC,
        src_reg: reg,
        dst_reg: reg,
        branch_cond: 0,
        cycles: 2,
        is_read: 0,
        is_write: 0,
        is_rmw: 0,
        sets_nz: 1,
        sets_c: 0,
        sets_v: 0,
        writes_reg: 1,
        illegal: 0
      }
    end

    def add_inc_dec_mem(opcode, mode, is_inc, name, cycles)
      @decode_table[opcode] = {
        addr_mode: mode,
        alu_op: is_inc ? ALU::OP_INC : ALU::OP_DEC,
        type: TYPE_INC_DEC,
        src_reg: REG_A,
        dst_reg: REG_A,
        branch_cond: 0,
        cycles: cycles,
        is_read: 1,
        is_write: 1,
        is_rmw: 1,
        sets_nz: 1,
        sets_c: 0,
        sets_v: 0,
        illegal: 0
      }
    end

    def add_shift(opcode, mode, alu_op, cycles)
      is_acc = (mode == AddressGenerator::MODE_ACCUMULATOR)
      @decode_table[opcode] = {
        addr_mode: mode,
        alu_op: alu_op,
        type: TYPE_SHIFT,
        src_reg: REG_A,
        dst_reg: REG_A,
        branch_cond: 0,
        cycles: cycles,
        is_read: is_acc ? 0 : 1,
        is_write: is_acc ? 0 : 1,
        is_rmw: is_acc ? 0 : 1,
        sets_nz: 1,
        sets_c: 1,
        sets_v: 0,
        writes_reg: is_acc ? 1 : 0,  # Accumulator mode writes to A
        illegal: 0
      }
    end

    def add_branch(opcode, condition)
      @decode_table[opcode] = {
        addr_mode: AddressGenerator::MODE_RELATIVE,
        alu_op: ALU::OP_NOP,
        type: TYPE_BRANCH,
        src_reg: REG_A,
        dst_reg: REG_A,
        branch_cond: condition,
        cycles: 2,
        is_read: 0,
        is_write: 0,
        is_rmw: 0,
        sets_nz: 0,
        sets_c: 0,
        sets_v: 0,
        illegal: 0
      }
    end

    def add_jump(opcode, mode, name, cycles)
      @decode_table[opcode] = {
        addr_mode: mode,
        alu_op: ALU::OP_NOP,
        type: TYPE_JUMP,
        src_reg: REG_A,
        dst_reg: REG_A,
        branch_cond: 0,
        cycles: cycles,
        is_read: 0,
        is_write: (name == :JSR) ? 1 : 0,  # JSR writes to stack
        is_rmw: 0,
        sets_nz: (name == :RTI) ? 1 : 0,   # RTI restores flags
        sets_c: (name == :RTI) ? 1 : 0,
        sets_v: (name == :RTI) ? 1 : 0,
        illegal: 0,
        mnemonic: name
      }
    end

    def add_stack(opcode, name, is_push, is_status)
      @decode_table[opcode] = {
        addr_mode: AddressGenerator::MODE_IMPLIED,
        alu_op: ALU::OP_TST,
        type: TYPE_STACK,
        src_reg: REG_A,
        dst_reg: REG_A,
        branch_cond: 0,
        cycles: is_push ? 3 : 4,
        is_read: is_push ? 0 : 1,
        is_write: is_push ? 1 : 0,
        is_rmw: 0,
        sets_nz: (!is_push && !is_status) ? 1 : 0,  # PLA sets N,Z
        sets_c: (!is_push && is_status) ? 1 : 0,    # PLP restores all
        sets_v: (!is_push && is_status) ? 1 : 0,
        illegal: 0,
        mnemonic: name,
        is_push: is_push,
        is_status: is_status
      }
    end

    def add_flag(opcode, name, flag, value)
      @decode_table[opcode] = {
        addr_mode: AddressGenerator::MODE_IMPLIED,
        alu_op: ALU::OP_NOP,
        type: TYPE_FLAG,
        src_reg: REG_A,
        dst_reg: REG_A,
        branch_cond: 0,
        cycles: 2,
        is_read: 0,
        is_write: 0,
        is_rmw: 0,
        sets_nz: 0,
        sets_c: (flag == :c) ? 1 : 0,
        sets_v: (flag == :v) ? 1 : 0,
        illegal: 0,
        mnemonic: name,
        flag: flag,
        flag_value: value
      }
    end
  end
end
