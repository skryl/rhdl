# MOS 6502 Instruction Decoder - Synthesizable DSL Version
# Decodes opcodes into control signals
# Uses behavior DSL for ROM-style lookup table synthesis

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative 'alu'

module MOS6502
  class InstructionDecoder < RHDL::HDL::Component
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

    input :opcode, width: 8

    output :addr_mode, width: 4
    output :alu_op, width: 4
    output :instr_type, width: 4
    output :src_reg, width: 2
    output :dst_reg, width: 2
    output :branch_cond, width: 3
    output :cycles_base, width: 3
    output :is_read
    output :is_write
    output :is_rmw
    output :sets_nz
    output :sets_c
    output :sets_v
    output :writes_reg
    output :is_status_op
    output :illegal

    # Build decode table as class-level data for DSL synthesis
    def self.build_decode_data
      @decode_data ||= begin
        data = {}

        # Helper to add entries
        add = ->(opcode, info) { data[opcode] = info }

        # ADC - Add with Carry
        add[0x69, { addr_mode: MODE_IMMEDIATE,   alu_op: OP_ADC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0x65, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_ADC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 3, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0x75, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_ADC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0x6D, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_ADC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0x7D, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_ADC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0x79, { addr_mode: MODE_ABSOLUTE_Y,  alu_op: OP_ADC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0x61, { addr_mode: MODE_INDEXED_IND, alu_op: OP_ADC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0x71, { addr_mode: MODE_INDIRECT_IDX, alu_op: OP_ADC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]

        # SBC - Subtract with Carry
        add[0xE9, { addr_mode: MODE_IMMEDIATE,   alu_op: OP_SBC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0xE5, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_SBC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 3, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0xF5, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_SBC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0xED, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_SBC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0xFD, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_SBC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0xF9, { addr_mode: MODE_ABSOLUTE_Y,  alu_op: OP_SBC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0xE1, { addr_mode: MODE_INDEXED_IND, alu_op: OP_SBC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]
        add[0xF1, { addr_mode: MODE_INDIRECT_IDX, alu_op: OP_SBC, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 1, writes_reg: 1, is_status: 0 }]

        # AND - Logical AND
        add[0x29, { addr_mode: MODE_IMMEDIATE,   alu_op: OP_AND, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x25, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_AND, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 3, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x35, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_AND, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x2D, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_AND, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x3D, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_AND, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x39, { addr_mode: MODE_ABSOLUTE_Y,  alu_op: OP_AND, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x21, { addr_mode: MODE_INDEXED_IND, alu_op: OP_AND, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x31, { addr_mode: MODE_INDIRECT_IDX, alu_op: OP_AND, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]

        # ORA - Logical OR
        add[0x09, { addr_mode: MODE_IMMEDIATE,   alu_op: OP_ORA, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x05, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_ORA, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 3, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x15, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_ORA, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x0D, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_ORA, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x1D, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_ORA, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x19, { addr_mode: MODE_ABSOLUTE_Y,  alu_op: OP_ORA, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x01, { addr_mode: MODE_INDEXED_IND, alu_op: OP_ORA, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x11, { addr_mode: MODE_INDIRECT_IDX, alu_op: OP_ORA, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]

        # EOR - Logical XOR
        add[0x49, { addr_mode: MODE_IMMEDIATE,   alu_op: OP_EOR, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x45, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_EOR, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 3, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x55, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_EOR, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x4D, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_EOR, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x5D, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_EOR, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x59, { addr_mode: MODE_ABSOLUTE_Y,  alu_op: OP_EOR, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x41, { addr_mode: MODE_INDEXED_IND, alu_op: OP_EOR, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x51, { addr_mode: MODE_INDIRECT_IDX, alu_op: OP_EOR, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]

        # CMP - Compare Accumulator
        add[0xC9, { addr_mode: MODE_IMMEDIATE,   alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xC5, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 3, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xD5, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xCD, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xDD, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xD9, { addr_mode: MODE_ABSOLUTE_Y,  alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xC1, { addr_mode: MODE_INDEXED_IND, alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xD1, { addr_mode: MODE_INDIRECT_IDX, alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]

        # CPX - Compare X
        add[0xE0, { addr_mode: MODE_IMMEDIATE, alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xE4, { addr_mode: MODE_ZERO_PAGE, alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 3, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xEC, { addr_mode: MODE_ABSOLUTE,  alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]

        # CPY - Compare Y
        add[0xC0, { addr_mode: MODE_IMMEDIATE, alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xC4, { addr_mode: MODE_ZERO_PAGE, alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 3, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xCC, { addr_mode: MODE_ABSOLUTE,  alu_op: OP_CMP, type: TYPE_ALU, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]

        # BIT - Bit Test
        add[0x24, { addr_mode: MODE_ZERO_PAGE, alu_op: OP_BIT, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 3, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 1, writes_reg: 0, is_status: 0 }]
        add[0x2C, { addr_mode: MODE_ABSOLUTE,  alu_op: OP_BIT, type: TYPE_ALU, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 1, writes_reg: 0, is_status: 0 }]

        # LDA - Load Accumulator
        add[0xA9, { addr_mode: MODE_IMMEDIATE,   alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xA5, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 3, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xB5, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xAD, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xBD, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xB9, { addr_mode: MODE_ABSOLUTE_Y,  alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xA1, { addr_mode: MODE_INDEXED_IND, alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xB1, { addr_mode: MODE_INDIRECT_IDX, alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]

        # LDX - Load X
        add[0xA2, { addr_mode: MODE_IMMEDIATE,   alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xA6, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 3, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xB6, { addr_mode: MODE_ZERO_PAGE_Y, alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xAE, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xBE, { addr_mode: MODE_ABSOLUTE_Y,  alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]

        # LDY - Load Y
        add[0xA0, { addr_mode: MODE_IMMEDIATE,   alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xA4, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 3, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xB4, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xAC, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0xBC, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_TST, type: TYPE_LOAD, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]

        # STA - Store Accumulator
        add[0x85, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 3, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x95, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x8D, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x9D, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x99, { addr_mode: MODE_ABSOLUTE_Y,  alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x81, { addr_mode: MODE_INDEXED_IND, alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x91, { addr_mode: MODE_INDIRECT_IDX, alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]

        # STX - Store X
        add[0x86, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 3, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x96, { addr_mode: MODE_ZERO_PAGE_Y, alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 4, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x8E, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 4, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]

        # STY - Store Y
        add[0x84, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 3, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x94, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 4, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x8C, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_NOP, type: TYPE_STORE, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 4, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]

        # Register Transfers
        add[0xAA, { addr_mode: MODE_IMPLIED, alu_op: OP_TST, type: TYPE_TRANSFER, src_reg: REG_A, dst_reg: REG_X, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]  # TAX
        add[0x8A, { addr_mode: MODE_IMPLIED, alu_op: OP_TST, type: TYPE_TRANSFER, src_reg: REG_X, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]  # TXA
        add[0xA8, { addr_mode: MODE_IMPLIED, alu_op: OP_TST, type: TYPE_TRANSFER, src_reg: REG_A, dst_reg: REG_Y, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]  # TAY
        add[0x98, { addr_mode: MODE_IMPLIED, alu_op: OP_TST, type: TYPE_TRANSFER, src_reg: REG_Y, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]  # TYA
        add[0xBA, { addr_mode: MODE_IMPLIED, alu_op: OP_TST, type: TYPE_TRANSFER, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]  # TSX
        add[0x9A, { addr_mode: MODE_IMPLIED, alu_op: OP_TST, type: TYPE_TRANSFER, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]  # TXS

        # Increment/Decrement Register
        add[0xE8, { addr_mode: MODE_IMPLIED, alu_op: OP_INC, type: TYPE_INC_DEC, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]  # INX
        add[0xCA, { addr_mode: MODE_IMPLIED, alu_op: OP_DEC, type: TYPE_INC_DEC, src_reg: REG_X, dst_reg: REG_X, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]  # DEX
        add[0xC8, { addr_mode: MODE_IMPLIED, alu_op: OP_INC, type: TYPE_INC_DEC, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]  # INY
        add[0x88, { addr_mode: MODE_IMPLIED, alu_op: OP_DEC, type: TYPE_INC_DEC, src_reg: REG_Y, dst_reg: REG_Y, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]  # DEY

        # Increment/Decrement Memory
        add[0xE6, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_INC, type: TYPE_INC_DEC, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xF6, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_INC, type: TYPE_INC_DEC, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xEE, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_INC, type: TYPE_INC_DEC, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xFE, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_INC, type: TYPE_INC_DEC, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 7, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xC6, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_DEC, type: TYPE_INC_DEC, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xD6, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_DEC, type: TYPE_INC_DEC, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xCE, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_DEC, type: TYPE_INC_DEC, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xDE, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_DEC, type: TYPE_INC_DEC, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 7, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]

        # Shift/Rotate
        add[0x0A, { addr_mode: MODE_ACCUMULATOR, alu_op: OP_ASL, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x06, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_ASL, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x16, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_ASL, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x0E, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_ASL, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x1E, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_ASL, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 7, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]

        add[0x4A, { addr_mode: MODE_ACCUMULATOR, alu_op: OP_LSR, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x46, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_LSR, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x56, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_LSR, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x4E, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_LSR, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x5E, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_LSR, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 7, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]

        add[0x2A, { addr_mode: MODE_ACCUMULATOR, alu_op: OP_ROL, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x26, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_ROL, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x36, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_ROL, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x2E, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_ROL, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x3E, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_ROL, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 7, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]

        add[0x6A, { addr_mode: MODE_ACCUMULATOR, alu_op: OP_ROR, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 1, is_status: 0 }]
        add[0x66, { addr_mode: MODE_ZERO_PAGE,   alu_op: OP_ROR, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x76, { addr_mode: MODE_ZERO_PAGE_X, alu_op: OP_ROR, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x6E, { addr_mode: MODE_ABSOLUTE,    alu_op: OP_ROR, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x7E, { addr_mode: MODE_ABSOLUTE_X,  alu_op: OP_ROR, type: TYPE_SHIFT, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 7, is_read: 1, is_write: 1, is_rmw: 1, sets_nz: 1, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]

        # Branches
        add[0x10, { addr_mode: MODE_RELATIVE, alu_op: OP_NOP, type: TYPE_BRANCH, src_reg: REG_A, dst_reg: REG_A, branch_cond: BRANCH_BPL, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x30, { addr_mode: MODE_RELATIVE, alu_op: OP_NOP, type: TYPE_BRANCH, src_reg: REG_A, dst_reg: REG_A, branch_cond: BRANCH_BMI, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x50, { addr_mode: MODE_RELATIVE, alu_op: OP_NOP, type: TYPE_BRANCH, src_reg: REG_A, dst_reg: REG_A, branch_cond: BRANCH_BVC, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x70, { addr_mode: MODE_RELATIVE, alu_op: OP_NOP, type: TYPE_BRANCH, src_reg: REG_A, dst_reg: REG_A, branch_cond: BRANCH_BVS, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0x90, { addr_mode: MODE_RELATIVE, alu_op: OP_NOP, type: TYPE_BRANCH, src_reg: REG_A, dst_reg: REG_A, branch_cond: BRANCH_BCC, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xB0, { addr_mode: MODE_RELATIVE, alu_op: OP_NOP, type: TYPE_BRANCH, src_reg: REG_A, dst_reg: REG_A, branch_cond: BRANCH_BCS, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xD0, { addr_mode: MODE_RELATIVE, alu_op: OP_NOP, type: TYPE_BRANCH, src_reg: REG_A, dst_reg: REG_A, branch_cond: BRANCH_BNE, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]
        add[0xF0, { addr_mode: MODE_RELATIVE, alu_op: OP_NOP, type: TYPE_BRANCH, src_reg: REG_A, dst_reg: REG_A, branch_cond: BRANCH_BEQ, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]

        # Jumps
        add[0x4C, { addr_mode: MODE_ABSOLUTE, alu_op: OP_NOP, type: TYPE_JUMP, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 3, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]  # JMP abs
        add[0x6C, { addr_mode: MODE_INDIRECT, alu_op: OP_NOP, type: TYPE_JUMP, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 5, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]  # JMP ind
        add[0x20, { addr_mode: MODE_ABSOLUTE, alu_op: OP_NOP, type: TYPE_JUMP, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]  # JSR
        add[0x60, { addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_JUMP, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]  # RTS
        add[0x40, { addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_JUMP, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 6, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]  # RTI

        # Stack Operations
        add[0x48, { addr_mode: MODE_IMPLIED, alu_op: OP_TST, type: TYPE_STACK, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 3, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]  # PHA
        add[0x08, { addr_mode: MODE_IMPLIED, alu_op: OP_TST, type: TYPE_STACK, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 3, is_read: 0, is_write: 1, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 1 }]  # PHP
        add[0x68, { addr_mode: MODE_IMPLIED, alu_op: OP_TST, type: TYPE_STACK, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 1, sets_c: 0, sets_v: 0, writes_reg: 1, is_status: 0 }]  # PLA
        add[0x28, { addr_mode: MODE_IMPLIED, alu_op: OP_TST, type: TYPE_STACK, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 4, is_read: 1, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 1, sets_v: 1, writes_reg: 0, is_status: 1 }]  # PLP

        # Flag Operations
        add[0x18, { addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_FLAG, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]  # CLC
        add[0x38, { addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_FLAG, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 1, sets_v: 0, writes_reg: 0, is_status: 0 }]  # SEC
        add[0x58, { addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_FLAG, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]  # CLI
        add[0x78, { addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_FLAG, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]  # SEI
        add[0xB8, { addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_FLAG, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 1, writes_reg: 0, is_status: 0 }]  # CLV
        add[0xD8, { addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_FLAG, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]  # CLD
        add[0xF8, { addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_FLAG, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]  # SED

        # NOP
        add[0xEA, { addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_NOP, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 2, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]

        # BRK
        add[0x00, { addr_mode: MODE_IMPLIED, alu_op: OP_NOP, type: TYPE_BRK, src_reg: REG_A, dst_reg: REG_A, branch_cond: 0, cycles: 7, is_read: 0, is_write: 0, is_rmw: 0, sets_nz: 0, sets_c: 0, sets_v: 0, writes_reg: 0, is_status: 0 }]

        data
      end
    end

    # Behavior block - dynamically generate case_select entries from decode table
    class << self
      def _generate_behavior
        decode_data = build_decode_data

        # Build case hashes for each output
        addr_mode_cases = {}
        alu_op_cases = {}
        instr_type_cases = {}
        src_reg_cases = {}
        dst_reg_cases = {}
        branch_cond_cases = {}
        cycles_base_cases = {}
        is_read_cases = {}
        is_write_cases = {}
        is_rmw_cases = {}
        sets_nz_cases = {}
        sets_c_cases = {}
        sets_v_cases = {}
        writes_reg_cases = {}
        is_status_op_cases = {}

        decode_data.each do |opcode, info|
          addr_mode_cases[opcode] = info[:addr_mode]
          alu_op_cases[opcode] = info[:alu_op]
          instr_type_cases[opcode] = info[:type]
          src_reg_cases[opcode] = info[:src_reg]
          dst_reg_cases[opcode] = info[:dst_reg]
          branch_cond_cases[opcode] = info[:branch_cond]
          cycles_base_cases[opcode] = info[:cycles]
          is_read_cases[opcode] = info[:is_read]
          is_write_cases[opcode] = info[:is_write]
          is_rmw_cases[opcode] = info[:is_rmw]
          sets_nz_cases[opcode] = info[:sets_nz]
          sets_c_cases[opcode] = info[:sets_c]
          sets_v_cases[opcode] = info[:sets_v]
          writes_reg_cases[opcode] = info[:writes_reg]
          is_status_op_cases[opcode] = info[:is_status]
        end

        {
          addr_mode: addr_mode_cases,
          alu_op: alu_op_cases,
          instr_type: instr_type_cases,
          src_reg: src_reg_cases,
          dst_reg: dst_reg_cases,
          branch_cond: branch_cond_cases,
          cycles_base: cycles_base_cases,
          is_read: is_read_cases,
          is_write: is_write_cases,
          is_rmw: is_rmw_cases,
          sets_nz: sets_nz_cases,
          sets_c: sets_c_cases,
          sets_v: sets_v_cases,
          writes_reg: writes_reg_cases,
          is_status_op: is_status_op_cases
        }
      end
    end

    # Pre-compute case data at class load time
    DECODE_CASES = _generate_behavior

    # Behavior block for combinational synthesis
    behavior do
      addr_mode <= case_select(opcode, DECODE_CASES[:addr_mode], default: MODE_IMPLIED)
      alu_op <= case_select(opcode, DECODE_CASES[:alu_op], default: OP_NOP)
      instr_type <= case_select(opcode, DECODE_CASES[:instr_type], default: TYPE_NOP)
      src_reg <= case_select(opcode, DECODE_CASES[:src_reg], default: REG_A)
      dst_reg <= case_select(opcode, DECODE_CASES[:dst_reg], default: REG_A)
      branch_cond <= case_select(opcode, DECODE_CASES[:branch_cond], default: 0)
      cycles_base <= case_select(opcode, DECODE_CASES[:cycles_base], default: 2)
      is_read <= case_select(opcode, DECODE_CASES[:is_read], default: 0)
      is_write <= case_select(opcode, DECODE_CASES[:is_write], default: 0)
      is_rmw <= case_select(opcode, DECODE_CASES[:is_rmw], default: 0)
      sets_nz <= case_select(opcode, DECODE_CASES[:sets_nz], default: 0)
      sets_c <= case_select(opcode, DECODE_CASES[:sets_c], default: 0)
      sets_v <= case_select(opcode, DECODE_CASES[:sets_v], default: 0)
      writes_reg <= case_select(opcode, DECODE_CASES[:writes_reg], default: 0)
      is_status_op <= case_select(opcode, DECODE_CASES[:is_status_op], default: 0)
      # illegal: 1 if opcode not in table
      illegal <= case_select(opcode, DECODE_CASES[:addr_mode].transform_values { 0 }, default: 1)
    end

  end
end
