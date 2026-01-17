# MOS 6502 Instruction Decoder - Synthesizable DSL Version
# Decodes opcodes into control signals
# Uses lookup table pattern for synthesis as ROM or combinational logic

require_relative '../../lib/rhdl'
require_relative '../../lib/rhdl/dsl/behavior'
require_relative 'alu'

module MOS6502S
  class InstructionDecoder < RHDL::HDL::SimComponent
    include RHDL::DSL::Behavior
    # Instruction types
    TYPE_ALU       = 0x00
    TYPE_LOAD      = 0x01
    TYPE_STORE     = 0x02
    TYPE_TRANSFER  = 0x03
    TYPE_INC_DEC   = 0x04
    TYPE_SHIFT     = 0x05
    TYPE_BRANCH    = 0x06
    TYPE_JUMP      = 0x07
    TYPE_STACK     = 0x08
    TYPE_FLAG      = 0x09
    TYPE_NOP       = 0x0A
    TYPE_BRK       = 0x0B

    # Branch conditions
    BRANCH_BPL = 0
    BRANCH_BMI = 1
    BRANCH_BVC = 2
    BRANCH_BVS = 3
    BRANCH_BCC = 4
    BRANCH_BCS = 5
    BRANCH_BNE = 6
    BRANCH_BEQ = 7

    # Addressing modes
    MODE_IMPLIED     = 0x00
    MODE_ACCUMULATOR = 0x01
    MODE_IMMEDIATE   = 0x02
    MODE_ZERO_PAGE   = 0x03
    MODE_ZERO_PAGE_X = 0x04
    MODE_ZERO_PAGE_Y = 0x05
    MODE_ABSOLUTE    = 0x06
    MODE_ABSOLUTE_X  = 0x07
    MODE_ABSOLUTE_Y  = 0x08
    MODE_INDIRECT    = 0x09
    MODE_INDEXED_IND = 0x0A
    MODE_INDIRECT_IDX = 0x0B
    MODE_RELATIVE    = 0x0C
    MODE_STACK       = 0x0D

    # ALU operations
    OP_ADC = 0x00
    OP_SBC = 0x01
    OP_AND = 0x02
    OP_ORA = 0x03
    OP_EOR = 0x04
    OP_ASL = 0x05
    OP_LSR = 0x06
    OP_ROL = 0x07
    OP_ROR = 0x08
    OP_INC = 0x09
    OP_DEC = 0x0A
    OP_CMP = 0x0B
    OP_BIT = 0x0C
    OP_TST = 0x0D
    OP_NOP = 0x0F

    # Registers
    REG_A = 0
    REG_X = 1
    REG_Y = 2

    port_input :opcode, width: 8

    port_output :addr_mode, width: 4
    port_output :alu_op, width: 4
    port_output :instr_type, width: 4
    port_output :src_reg, width: 2
    port_output :dst_reg, width: 2
    port_output :branch_cond, width: 3
    port_output :cycles_base, width: 3
    port_output :is_read
    port_output :is_write
    port_output :is_rmw
    port_output :sets_nz
    port_output :sets_c
    port_output :sets_v
    port_output :writes_reg
    port_output :is_status_op
    port_output :illegal

    def initialize(name = nil)
      super(name)
      build_decode_table
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
      out_set(:is_status_op, info[:is_status] ? 1 : 0)
      out_set(:illegal, info[:illegal])
    end

    private

    def illegal_opcode
      {
        addr_mode: MODE_IMPLIED,
        alu_op: OP_NOP,
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

      # === ADC - Add with Carry ===
      add_alu(0x69, MODE_IMMEDIATE,   OP_ADC, 2)
      add_alu(0x65, MODE_ZERO_PAGE,   OP_ADC, 3)
      add_alu(0x75, MODE_ZERO_PAGE_X, OP_ADC, 4)
      add_alu(0x6D, MODE_ABSOLUTE,    OP_ADC, 4)
      add_alu(0x7D, MODE_ABSOLUTE_X,  OP_ADC, 4)
      add_alu(0x79, MODE_ABSOLUTE_Y,  OP_ADC, 4)
      add_alu(0x61, MODE_INDEXED_IND, OP_ADC, 6)
      add_alu(0x71, MODE_INDIRECT_IDX, OP_ADC, 5)

      # === SBC - Subtract with Carry ===
      add_alu(0xE9, MODE_IMMEDIATE,   OP_SBC, 2)
      add_alu(0xE5, MODE_ZERO_PAGE,   OP_SBC, 3)
      add_alu(0xF5, MODE_ZERO_PAGE_X, OP_SBC, 4)
      add_alu(0xED, MODE_ABSOLUTE,    OP_SBC, 4)
      add_alu(0xFD, MODE_ABSOLUTE_X,  OP_SBC, 4)
      add_alu(0xF9, MODE_ABSOLUTE_Y,  OP_SBC, 4)
      add_alu(0xE1, MODE_INDEXED_IND, OP_SBC, 6)
      add_alu(0xF1, MODE_INDIRECT_IDX, OP_SBC, 5)

      # === AND - Logical AND ===
      add_alu(0x29, MODE_IMMEDIATE,   OP_AND, 2)
      add_alu(0x25, MODE_ZERO_PAGE,   OP_AND, 3)
      add_alu(0x35, MODE_ZERO_PAGE_X, OP_AND, 4)
      add_alu(0x2D, MODE_ABSOLUTE,    OP_AND, 4)
      add_alu(0x3D, MODE_ABSOLUTE_X,  OP_AND, 4)
      add_alu(0x39, MODE_ABSOLUTE_Y,  OP_AND, 4)
      add_alu(0x21, MODE_INDEXED_IND, OP_AND, 6)
      add_alu(0x31, MODE_INDIRECT_IDX, OP_AND, 5)

      # === ORA - Logical OR ===
      add_alu(0x09, MODE_IMMEDIATE,   OP_ORA, 2)
      add_alu(0x05, MODE_ZERO_PAGE,   OP_ORA, 3)
      add_alu(0x15, MODE_ZERO_PAGE_X, OP_ORA, 4)
      add_alu(0x0D, MODE_ABSOLUTE,    OP_ORA, 4)
      add_alu(0x1D, MODE_ABSOLUTE_X,  OP_ORA, 4)
      add_alu(0x19, MODE_ABSOLUTE_Y,  OP_ORA, 4)
      add_alu(0x01, MODE_INDEXED_IND, OP_ORA, 6)
      add_alu(0x11, MODE_INDIRECT_IDX, OP_ORA, 5)

      # === EOR - Logical XOR ===
      add_alu(0x49, MODE_IMMEDIATE,   OP_EOR, 2)
      add_alu(0x45, MODE_ZERO_PAGE,   OP_EOR, 3)
      add_alu(0x55, MODE_ZERO_PAGE_X, OP_EOR, 4)
      add_alu(0x4D, MODE_ABSOLUTE,    OP_EOR, 4)
      add_alu(0x5D, MODE_ABSOLUTE_X,  OP_EOR, 4)
      add_alu(0x59, MODE_ABSOLUTE_Y,  OP_EOR, 4)
      add_alu(0x41, MODE_INDEXED_IND, OP_EOR, 6)
      add_alu(0x51, MODE_INDIRECT_IDX, OP_EOR, 5)

      # === CMP - Compare Accumulator ===
      add_cmp(0xC9, MODE_IMMEDIATE,   REG_A, 2)
      add_cmp(0xC5, MODE_ZERO_PAGE,   REG_A, 3)
      add_cmp(0xD5, MODE_ZERO_PAGE_X, REG_A, 4)
      add_cmp(0xCD, MODE_ABSOLUTE,    REG_A, 4)
      add_cmp(0xDD, MODE_ABSOLUTE_X,  REG_A, 4)
      add_cmp(0xD9, MODE_ABSOLUTE_Y,  REG_A, 4)
      add_cmp(0xC1, MODE_INDEXED_IND, REG_A, 6)
      add_cmp(0xD1, MODE_INDIRECT_IDX, REG_A, 5)

      # === CPX - Compare X ===
      add_cmp(0xE0, MODE_IMMEDIATE, REG_X, 2)
      add_cmp(0xE4, MODE_ZERO_PAGE, REG_X, 3)
      add_cmp(0xEC, MODE_ABSOLUTE,  REG_X, 4)

      # === CPY - Compare Y ===
      add_cmp(0xC0, MODE_IMMEDIATE, REG_Y, 2)
      add_cmp(0xC4, MODE_ZERO_PAGE, REG_Y, 3)
      add_cmp(0xCC, MODE_ABSOLUTE,  REG_Y, 4)

      # === BIT - Bit Test ===
      add_bit(0x24, MODE_ZERO_PAGE, 3)
      add_bit(0x2C, MODE_ABSOLUTE,  4)

      # === LDA - Load Accumulator ===
      add_load(0xA9, MODE_IMMEDIATE,   REG_A, 2)
      add_load(0xA5, MODE_ZERO_PAGE,   REG_A, 3)
      add_load(0xB5, MODE_ZERO_PAGE_X, REG_A, 4)
      add_load(0xAD, MODE_ABSOLUTE,    REG_A, 4)
      add_load(0xBD, MODE_ABSOLUTE_X,  REG_A, 4)
      add_load(0xB9, MODE_ABSOLUTE_Y,  REG_A, 4)
      add_load(0xA1, MODE_INDEXED_IND, REG_A, 6)
      add_load(0xB1, MODE_INDIRECT_IDX, REG_A, 5)

      # === LDX - Load X ===
      add_load(0xA2, MODE_IMMEDIATE,   REG_X, 2)
      add_load(0xA6, MODE_ZERO_PAGE,   REG_X, 3)
      add_load(0xB6, MODE_ZERO_PAGE_Y, REG_X, 4)
      add_load(0xAE, MODE_ABSOLUTE,    REG_X, 4)
      add_load(0xBE, MODE_ABSOLUTE_Y,  REG_X, 4)

      # === LDY - Load Y ===
      add_load(0xA0, MODE_IMMEDIATE,   REG_Y, 2)
      add_load(0xA4, MODE_ZERO_PAGE,   REG_Y, 3)
      add_load(0xB4, MODE_ZERO_PAGE_X, REG_Y, 4)
      add_load(0xAC, MODE_ABSOLUTE,    REG_Y, 4)
      add_load(0xBC, MODE_ABSOLUTE_X,  REG_Y, 4)

      # === STA - Store Accumulator ===
      add_store(0x85, MODE_ZERO_PAGE,   REG_A, 3)
      add_store(0x95, MODE_ZERO_PAGE_X, REG_A, 4)
      add_store(0x8D, MODE_ABSOLUTE,    REG_A, 4)
      add_store(0x9D, MODE_ABSOLUTE_X,  REG_A, 5)
      add_store(0x99, MODE_ABSOLUTE_Y,  REG_A, 5)
      add_store(0x81, MODE_INDEXED_IND, REG_A, 6)
      add_store(0x91, MODE_INDIRECT_IDX, REG_A, 6)

      # === STX - Store X ===
      add_store(0x86, MODE_ZERO_PAGE,   REG_X, 3)
      add_store(0x96, MODE_ZERO_PAGE_Y, REG_X, 4)
      add_store(0x8E, MODE_ABSOLUTE,    REG_X, 4)

      # === STY - Store Y ===
      add_store(0x84, MODE_ZERO_PAGE,   REG_Y, 3)
      add_store(0x94, MODE_ZERO_PAGE_X, REG_Y, 4)
      add_store(0x8C, MODE_ABSOLUTE,    REG_Y, 4)

      # === Register Transfers ===
      add_transfer(0xAA, REG_A, REG_X, true)   # TAX
      add_transfer(0x8A, REG_X, REG_A, true)   # TXA
      add_transfer(0xA8, REG_A, REG_Y, true)   # TAY
      add_transfer(0x98, REG_Y, REG_A, true)   # TYA
      add_transfer(0xBA, REG_X, REG_X, true)   # TSX
      add_transfer(0x9A, REG_X, REG_X, false)  # TXS (no flags)

      # === Increment/Decrement Register ===
      add_inc_dec_reg(0xE8, REG_X, true)   # INX
      add_inc_dec_reg(0xCA, REG_X, false)  # DEX
      add_inc_dec_reg(0xC8, REG_Y, true)   # INY
      add_inc_dec_reg(0x88, REG_Y, false)  # DEY

      # === Increment/Decrement Memory ===
      add_inc_dec_mem(0xE6, MODE_ZERO_PAGE,   true, 5)
      add_inc_dec_mem(0xF6, MODE_ZERO_PAGE_X, true, 6)
      add_inc_dec_mem(0xEE, MODE_ABSOLUTE,    true, 6)
      add_inc_dec_mem(0xFE, MODE_ABSOLUTE_X,  true, 7)
      add_inc_dec_mem(0xC6, MODE_ZERO_PAGE,   false, 5)
      add_inc_dec_mem(0xD6, MODE_ZERO_PAGE_X, false, 6)
      add_inc_dec_mem(0xCE, MODE_ABSOLUTE,    false, 6)
      add_inc_dec_mem(0xDE, MODE_ABSOLUTE_X,  false, 7)

      # === Shift/Rotate ===
      add_shift(0x0A, MODE_ACCUMULATOR, OP_ASL, 2)
      add_shift(0x06, MODE_ZERO_PAGE,   OP_ASL, 5)
      add_shift(0x16, MODE_ZERO_PAGE_X, OP_ASL, 6)
      add_shift(0x0E, MODE_ABSOLUTE,    OP_ASL, 6)
      add_shift(0x1E, MODE_ABSOLUTE_X,  OP_ASL, 7)

      add_shift(0x4A, MODE_ACCUMULATOR, OP_LSR, 2)
      add_shift(0x46, MODE_ZERO_PAGE,   OP_LSR, 5)
      add_shift(0x56, MODE_ZERO_PAGE_X, OP_LSR, 6)
      add_shift(0x4E, MODE_ABSOLUTE,    OP_LSR, 6)
      add_shift(0x5E, MODE_ABSOLUTE_X,  OP_LSR, 7)

      add_shift(0x2A, MODE_ACCUMULATOR, OP_ROL, 2)
      add_shift(0x26, MODE_ZERO_PAGE,   OP_ROL, 5)
      add_shift(0x36, MODE_ZERO_PAGE_X, OP_ROL, 6)
      add_shift(0x2E, MODE_ABSOLUTE,    OP_ROL, 6)
      add_shift(0x3E, MODE_ABSOLUTE_X,  OP_ROL, 7)

      add_shift(0x6A, MODE_ACCUMULATOR, OP_ROR, 2)
      add_shift(0x66, MODE_ZERO_PAGE,   OP_ROR, 5)
      add_shift(0x76, MODE_ZERO_PAGE_X, OP_ROR, 6)
      add_shift(0x6E, MODE_ABSOLUTE,    OP_ROR, 6)
      add_shift(0x7E, MODE_ABSOLUTE_X,  OP_ROR, 7)

      # === Branches ===
      add_branch(0x10, BRANCH_BPL)
      add_branch(0x30, BRANCH_BMI)
      add_branch(0x50, BRANCH_BVC)
      add_branch(0x70, BRANCH_BVS)
      add_branch(0x90, BRANCH_BCC)
      add_branch(0xB0, BRANCH_BCS)
      add_branch(0xD0, BRANCH_BNE)
      add_branch(0xF0, BRANCH_BEQ)

      # === Jumps ===
      add_jump(0x4C, MODE_ABSOLUTE, false, 3)  # JMP
      add_jump(0x6C, MODE_INDIRECT, false, 5)  # JMP indirect
      add_jump(0x20, MODE_ABSOLUTE, true, 6)   # JSR
      add_jump(0x60, MODE_IMPLIED, false, 6)   # RTS
      add_jump(0x40, MODE_IMPLIED, false, 6)   # RTI

      # === Stack Operations ===
      add_stack(0x48, true, false)   # PHA
      add_stack(0x08, true, true)    # PHP
      add_stack(0x68, false, false)  # PLA
      add_stack(0x28, false, true)   # PLP

      # === Flag Operations ===
      add_flag(0x18, :c, 0)  # CLC
      add_flag(0x38, :c, 1)  # SEC
      add_flag(0x58, :i, 0)  # CLI
      add_flag(0x78, :i, 1)  # SEI
      add_flag(0xB8, :v, 0)  # CLV
      add_flag(0xD8, :d, 0)  # CLD
      add_flag(0xF8, :d, 1)  # SED

      # === NOP ===
      @decode_table[0xEA] = {
        addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_NOP,
        src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2,
        is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, illegal: 0
      }

      # === BRK ===
      @decode_table[0x00] = {
        addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_BRK,
        src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 7,
        is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, illegal: 0
      }
    end

    def add_alu(opcode, mode, alu_op, cycles)
      @decode_table[opcode] = {
        addr_mode: mode, alu_op: alu_op, type: TYPE_ALU,
        src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: cycles,
        is_read: (mode == MODE_IMMEDIATE) ? 0 : 1, is_write: 0, is_rmw: 0,
        sets_nz: 1, sets_c: (alu_op == OP_ADC || alu_op == OP_SBC) ? 1 : 0,
        sets_v: (alu_op == OP_ADC || alu_op == OP_SBC) ? 1 : 0,
        writes_reg: 1, illegal: 0
      }
    end

    def add_cmp(opcode, mode, reg, cycles)
      @decode_table[opcode] = {
        addr_mode: mode, alu_op: OP_CMP, type: TYPE_ALU,
        src_reg: reg, dst_reg: reg, branch_cond: 0, cycles: cycles,
        is_read: (mode == MODE_IMMEDIATE) ? 0 : 1, is_write: 0, is_rmw: 0,
        sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, illegal: 0
      }
    end

    def add_bit(opcode, mode, cycles)
      @decode_table[opcode] = {
        addr_mode: mode, alu_op: OP_BIT, type: TYPE_ALU,
        src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: cycles,
        is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 1,
        writes_reg: 0, illegal: 0
      }
    end

    def add_load(opcode, mode, reg, cycles)
      @decode_table[opcode] = {
        addr_mode: mode, alu_op: OP_TST, type: TYPE_LOAD,
        src_reg: reg, dst_reg: reg, branch_cond: 0, cycles: cycles,
        is_read: (mode == MODE_IMMEDIATE) ? 0 : 1, is_write: 0, is_rmw: 0,
        sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, illegal: 0
      }
    end

    def add_store(opcode, mode, reg, cycles)
      @decode_table[opcode] = {
        addr_mode: mode, alu_op: OP_NOP, type: TYPE_STORE,
        src_reg: reg, dst_reg: reg, branch_cond: 0, cycles: cycles,
        is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, illegal: 0
      }
    end

    def add_transfer(opcode, src, dst, sets_flags)
      @decode_table[opcode] = {
        addr_mode: MODE_IMPLIED, alu_op: OP_TST, type: TYPE_TRANSFER,
        src_reg: src, dst_reg: dst, branch_cond: 0, cycles: 2,
        is_read: 0, is_write: 0, is_rmw: 0, sets_nz: sets_flags ? 1 : 0,
        sets_c: 0, sets_v: 0, writes_reg: sets_flags ? 1 : 0, illegal: 0
      }
    end

    def add_inc_dec_reg(opcode, reg, is_inc)
      @decode_table[opcode] = {
        addr_mode: MODE_IMPLIED, alu_op: is_inc ? OP_INC : OP_DEC, type: TYPE_INC_DEC,
        src_reg: reg, dst_reg: reg, branch_cond: 0, cycles: 2,
        is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0,
        writes_reg: 1, illegal: 0
      }
    end

    def add_inc_dec_mem(opcode, mode, is_inc, cycles)
      @decode_table[opcode] = {
        addr_mode: mode, alu_op: is_inc ? OP_INC : OP_DEC, type: TYPE_INC_DEC,
        src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: cycles,
        is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 0, sets_v: 0, illegal: 0
      }
    end

    def add_shift(opcode, mode, alu_op, cycles)
      is_acc = (mode == MODE_ACCUMULATOR)
      @decode_table[opcode] = {
        addr_mode: mode, alu_op: alu_op, type: TYPE_SHIFT,
        src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: cycles,
        is_read: is_acc ? 0 : 1, is_write: is_acc ? 0 : 1, is_rmw: is_acc ? 0 : 1,
        sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: is_acc ? 1 : 0, illegal: 0
      }
    end

    def add_branch(opcode, condition)
      @decode_table[opcode] = {
        addr_mode: MODE_RELATIVE, alu_op: OP_NOP, type: TYPE_BRANCH,
        src_reg: REG_A, dst_reg: REG_A, branch_cond: condition, cycles: 2,
        is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, illegal: 0
      }
    end

    def add_jump(opcode, mode, is_jsr, cycles)
      @decode_table[opcode] = {
        addr_mode: mode, alu_op: OP_NOP, type: TYPE_JUMP,
        src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: cycles,
        is_read: 0, is_write: is_jsr ? 1 : 0, is_rmw: 0,
        sets_nz: 0, sets_c: 0, sets_v: 0, illegal: 0
      }
    end

    def add_stack(opcode, is_push, is_status)
      @decode_table[opcode] = {
        addr_mode: MODE_IMPLIED, alu_op: OP_TST, type: TYPE_STACK,
        src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: is_push ? 3 : 4,
        is_read: is_push ? 0 : 1, is_write: is_push ? 1 : 0, is_rmw: 0,
        sets_nz: (!is_push && !is_status) ? 1 : 0,
        sets_c: (!is_push && is_status) ? 1 : 0,
        sets_v: (!is_push && is_status) ? 1 : 0,
        writes_reg: (!is_push && !is_status) ? 1 : 0,
        is_status: is_status,
        illegal: 0
      }
    end

    def add_flag(opcode, flag, value)
      @decode_table[opcode] = {
        addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_FLAG,
        src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2,
        is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0,
        sets_c: (flag == :c) ? 1 : 0, sets_v: (flag == :v) ? 1 : 0, illegal: 0
      }
    end

    public

    def self.to_verilog
      # Create an instance to build the decode table
      decoder = new('_verilog_gen')

      lines = []
      lines << "// MOS 6502 Instruction Decoder - Synthesizable Verilog"
      lines << "// Generated from RHDL DSL - 151 opcodes"
      lines << ""
      lines << "module mos6502s_instruction_decoder ("
      lines << "  input  [7:0] opcode,"
      lines << "  output reg [3:0] addr_mode,"
      lines << "  output reg [3:0] alu_op,"
      lines << "  output reg [3:0] instr_type,"
      lines << "  output reg [1:0] src_reg,"
      lines << "  output reg [1:0] dst_reg,"
      lines << "  output reg [2:0] branch_cond,"
      lines << "  output reg [2:0] cycles_base,"
      lines << "  output reg       is_read,"
      lines << "  output reg       is_write,"
      lines << "  output reg       is_rmw,"
      lines << "  output reg       sets_nz,"
      lines << "  output reg       sets_c,"
      lines << "  output reg       sets_v,"
      lines << "  output reg       writes_reg,"
      lines << "  output reg       is_status_op,"
      lines << "  output reg       illegal"
      lines << ");"
      lines << ""
      lines << "  always @* begin"
      lines << "    // Default: illegal opcode"
      lines << "    addr_mode = 4'd0;"
      lines << "    alu_op = 4'd15;"  # OP_NOP
      lines << "    instr_type = 4'd10;"  # TYPE_NOP
      lines << "    src_reg = 2'd0;"
      lines << "    dst_reg = 2'd0;"
      lines << "    branch_cond = 3'd0;"
      lines << "    cycles_base = 3'd2;"
      lines << "    is_read = 1'b0;"
      lines << "    is_write = 1'b0;"
      lines << "    is_rmw = 1'b0;"
      lines << "    sets_nz = 1'b0;"
      lines << "    sets_c = 1'b0;"
      lines << "    sets_v = 1'b0;"
      lines << "    writes_reg = 1'b0;"
      lines << "    is_status_op = 1'b0;"
      lines << "    illegal = 1'b1;"
      lines << ""
      lines << "    case (opcode)"

      # Generate case entries for each opcode
      decoder.instance_variable_get(:@decode_table).each do |opcode, info|
        lines << "      8'h#{opcode.to_s(16).upcase.rjust(2, '0')}: begin"
        lines << "        addr_mode = 4'd#{info[:addr_mode]};"
        lines << "        alu_op = 4'd#{info[:alu_op]};"
        lines << "        instr_type = 4'd#{info[:type]};"
        lines << "        src_reg = 2'd#{info[:src_reg]};"
        lines << "        dst_reg = 2'd#{info[:dst_reg]};"
        lines << "        branch_cond = 3'd#{info[:branch_cond]};"
        lines << "        cycles_base = 3'd#{info[:cycles]};"
        lines << "        is_read = 1'b#{info[:is_read]};"
        lines << "        is_write = 1'b#{info[:is_write]};"
        lines << "        is_rmw = 1'b#{info[:is_rmw]};"
        lines << "        sets_nz = 1'b#{info[:sets_nz]};"
        lines << "        sets_c = 1'b#{info[:sets_c]};"
        lines << "        sets_v = 1'b#{info[:sets_v]};"
        lines << "        writes_reg = 1'b#{info[:writes_reg] || 0};"
        lines << "        is_status_op = 1'b#{info[:is_status] ? 1 : 0};"
        lines << "        illegal = 1'b0;"
        lines << "      end"
      end

      lines << "      default: begin"
      lines << "        illegal = 1'b1;"
      lines << "      end"
      lines << "    endcase"
      lines << "  end"
      lines << ""
      lines << "endmodule"

      lines.join("\n")
    end
  end
end
