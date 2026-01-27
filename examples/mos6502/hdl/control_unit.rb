# MOS 6502 Control Unit - Synthesizable DSL Version
# State machine that sequences instruction execution
# Sequential - requires always @(posedge clk) for synthesis

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module MOS6502
  class ControlUnit < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential
    # CPU States (same as original)
    STATE_RESET       = 0x00  # Reset sequence
    STATE_FETCH       = 0x01  # Fetch opcode
    STATE_DECODE      = 0x02  # Decode instruction
    STATE_FETCH_OP1   = 0x03  # Fetch first operand byte
    STATE_FETCH_OP2   = 0x04  # Fetch second operand byte
    STATE_ADDR_LO     = 0x05  # Fetch address low byte (indirect)
    STATE_ADDR_HI     = 0x06  # Fetch address high byte (indirect)
    STATE_READ_MEM    = 0x07  # Read from effective address
    STATE_EXECUTE     = 0x08  # Execute ALU operation
    STATE_WRITE_MEM   = 0x09  # Write to effective address
    STATE_PUSH        = 0x0A  # Push to stack
    STATE_PULL        = 0x0B  # Pull from stack
    STATE_BRANCH      = 0x0C  # Branch decision
    STATE_BRANCH_TAKE = 0x0D  # Branch taken, add offset
    STATE_JSR_PUSH_HI = 0x0E  # JSR: push PC high
    STATE_JSR_PUSH_LO = 0x0F  # JSR: push PC low
    STATE_RTS_PULL_LO = 0x10  # RTS: pull PC low
    STATE_RTS_PULL_HI = 0x11  # RTS: pull PC high
    STATE_RTI_PULL_P  = 0x12  # RTI: pull status
    STATE_RTI_PULL_LO = 0x13  # RTI: pull PC low
    STATE_RTI_PULL_HI = 0x14  # RTI: pull PC high
    STATE_BRK_PUSH_HI = 0x15  # BRK: push PC high
    STATE_BRK_PUSH_LO = 0x16  # BRK: push PC low
    STATE_BRK_PUSH_P  = 0x17  # BRK: push status
    STATE_BRK_VEC_LO  = 0x18  # BRK: read vector low
    STATE_BRK_VEC_HI  = 0x19  # BRK: read vector high
    STATE_HALT        = 0xFF  # Halted

    # Reset vector address
    RESET_VECTOR = 0xFFFC
    IRQ_VECTOR   = 0xFFFE
    NMI_VECTOR   = 0xFFFA

    # Instruction type constants (from InstructionDecoder)
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

    # Addressing mode constants (from AddressGenerator)
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

    # Branch condition constants
    BRANCH_BPL = 0
    BRANCH_BMI = 1
    BRANCH_BVC = 2
    BRANCH_BVS = 3
    BRANCH_BCC = 4
    BRANCH_BCS = 5
    BRANCH_BNE = 6
    BRANCH_BEQ = 7

    input :clk
    input :rst
    input :rdy            # Ready signal (for single-stepping)

    # Decoded instruction info
    input :addr_mode, width: 4
    input :instr_type, width: 4
    input :branch_cond, width: 3
    input :is_read
    input :is_write
    input :is_rmw
    input :writes_reg             # Instruction writes to register
    input :is_status_op           # Stack operation on status register (PHP/PLP)

    # Status flags for branch decisions
    input :flag_n
    input :flag_v
    input :flag_z
    input :flag_c

    # Page crossing
    input :page_cross

    # Memory ready
    input :mem_ready

    # Control outputs
    output :state, width: 8         # Current state
    output :state_before, width: 8  # State before transition (for control alignment)
    output :state_pre, width: 8     # State before transition (alias for state_before)
    output :pc_inc                  # Increment program counter
    output :pc_load                 # Load program counter
    output :load_opcode             # Load instruction register
    output :load_operand_lo         # Load operand low byte
    output :load_operand_hi         # Load operand high byte
    output :load_addr_lo            # Load address latch low
    output :load_addr_hi            # Load address latch high
    output :load_data               # Load data latch
    output :mem_read                # Memory read enable
    output :mem_write               # Memory write enable
    output :addr_sel, width: 3      # Address source select
    output :data_sel, width: 3      # Data source select
    output :alu_enable              # Enable ALU operation
    output :reg_write               # Write to register file
    output :sp_inc                  # Increment stack pointer
    output :sp_dec                  # Decrement stack pointer
    output :update_flags            # Update status flags
    output :done                    # Instruction complete
    output :halted                  # CPU halted
    output :cycle_count, width: 32  # Total cycles executed
    output :reset_step, width: 8    # Reset sequence counter (internal)

    # Sequential block for state machine
    # State transitions happen on rising clock edge
    sequential clock: :clk, reset: :rst, reset_values: { state: STATE_RESET, reset_step: 0, cycle_count: 0 } do
      # Branch taken logic
      branch_taken_val = local(:branch_taken_val,
        case_select(branch_cond, {
          BRANCH_BPL => (flag_n == lit(0, width: 1)),
          BRANCH_BMI => (flag_n == lit(1, width: 1)),
          BRANCH_BVC => (flag_v == lit(0, width: 1)),
          BRANCH_BVS => (flag_v == lit(1, width: 1)),
          BRANCH_BCC => (flag_c == lit(0, width: 1)),
          BRANCH_BCS => (flag_c == lit(1, width: 1)),
          BRANCH_BNE => (flag_z == lit(0, width: 1)),
          BRANCH_BEQ => (flag_z == lit(1, width: 1))
        }, default: 0), width: 1)

      # Helper conditions
      needs_read_val = local(:needs_read_val, is_read | is_rmw, width: 1)
      is_implied_or_acc = local(:is_implied_or_acc,
        (addr_mode == lit(MODE_IMPLIED, width: 4)) | (addr_mode == lit(MODE_ACCUMULATOR, width: 4)), width: 1)

      # Next state after decode (complex logic)
      decode_alu_like = local(:decode_alu_like,
        (instr_type == lit(TYPE_ALU, width: 4)) |
        (instr_type == lit(TYPE_LOAD, width: 4)) |
        (instr_type == lit(TYPE_STORE, width: 4)) |
        (instr_type == lit(TYPE_INC_DEC, width: 4)) |
        (instr_type == lit(TYPE_SHIFT, width: 4)), width: 1)

      decode_next = local(:decode_next,
        mux(decode_alu_like,
          mux(is_implied_or_acc, lit(STATE_EXECUTE, width: 8), lit(STATE_FETCH_OP1, width: 8)),
          mux((instr_type == lit(TYPE_TRANSFER, width: 4)) |
              (instr_type == lit(TYPE_FLAG, width: 4)) |
              (instr_type == lit(TYPE_NOP, width: 4)),
            lit(STATE_EXECUTE, width: 8),
            mux(instr_type == lit(TYPE_BRANCH, width: 4),
              lit(STATE_FETCH_OP1, width: 8),
              mux(instr_type == lit(TYPE_JUMP, width: 4),
                mux(addr_mode == lit(MODE_IMPLIED, width: 4),
                  lit(STATE_RTS_PULL_LO, width: 8),
                  lit(STATE_FETCH_OP1, width: 8)),
                mux(instr_type == lit(TYPE_STACK, width: 4),
                  mux(is_write, lit(STATE_PUSH, width: 8), lit(STATE_PULL, width: 8)),
                  mux(instr_type == lit(TYPE_BRK, width: 4),
                    lit(STATE_BRK_PUSH_HI, width: 8),
                    lit(STATE_FETCH, width: 8))))))), width: 8)

      # Next state after fetch_op1
      is_zp_mode = local(:is_zp_mode,
        (addr_mode == lit(MODE_ZERO_PAGE, width: 4)) |
        (addr_mode == lit(MODE_ZERO_PAGE_X, width: 4)) |
        (addr_mode == lit(MODE_ZERO_PAGE_Y, width: 4)), width: 1)

      is_indirect_mode = local(:is_indirect_mode,
        (addr_mode == lit(MODE_INDEXED_IND, width: 4)) |
        (addr_mode == lit(MODE_INDIRECT_IDX, width: 4)), width: 1)

      fetch_op1_next = local(:fetch_op1_next,
        mux(addr_mode == lit(MODE_IMMEDIATE, width: 4),
          lit(STATE_EXECUTE, width: 8),
          mux(is_zp_mode,
            mux(needs_read_val, lit(STATE_READ_MEM, width: 8),
              mux(is_write, lit(STATE_WRITE_MEM, width: 8), lit(STATE_EXECUTE, width: 8))),
            mux(addr_mode == lit(MODE_RELATIVE, width: 4),
              lit(STATE_BRANCH, width: 8),
              mux(is_indirect_mode,
                lit(STATE_ADDR_LO, width: 8),
                lit(STATE_FETCH_OP2, width: 8))))), width: 8)

      # Next state after fetch_op2
      fetch_op2_next = local(:fetch_op2_next,
        mux(addr_mode == lit(MODE_INDIRECT, width: 4),
          lit(STATE_ADDR_LO, width: 8),
          mux((instr_type == lit(TYPE_JUMP, width: 4)) & is_write,
            lit(STATE_JSR_PUSH_HI, width: 8),
            mux(needs_read_val, lit(STATE_READ_MEM, width: 8),
              mux(is_write, lit(STATE_WRITE_MEM, width: 8), lit(STATE_EXECUTE, width: 8))))), width: 8)

      # Next state after addr_hi
      addr_hi_next = local(:addr_hi_next,
        mux(addr_mode == lit(MODE_INDIRECT, width: 4),
          lit(STATE_EXECUTE, width: 8),
          mux(needs_read_val, lit(STATE_READ_MEM, width: 8),
            mux(is_write, lit(STATE_WRITE_MEM, width: 8), lit(STATE_EXECUTE, width: 8)))), width: 8)

      # Only process when rdy is high
      rdy_active = rdy == lit(1, width: 1)

      # Increment cycle count when ready
      cycle_count <= mux(rdy_active, cycle_count + lit(1, width: 32), cycle_count)

      # Reset step counter (for reset sequence)
      reset_step <= mux(state == lit(STATE_RESET, width: 8),
        mux(rdy_active, (reset_step + lit(1, width: 8))[7..0], reset_step),
        lit(0, width: 8))

      # State machine transitions
      state <= mux(rdy_active,
        case_select(state, {
          STATE_RESET => mux(reset_step >= lit(5, width: 8), lit(STATE_FETCH, width: 8), lit(STATE_RESET, width: 8)),
          STATE_FETCH => lit(STATE_DECODE, width: 8),
          STATE_DECODE => decode_next,
          STATE_FETCH_OP1 => fetch_op1_next,
          STATE_FETCH_OP2 => fetch_op2_next,
          STATE_ADDR_LO => lit(STATE_ADDR_HI, width: 8),
          STATE_ADDR_HI => addr_hi_next,
          STATE_READ_MEM => lit(STATE_EXECUTE, width: 8),
          STATE_EXECUTE => mux(is_rmw, lit(STATE_WRITE_MEM, width: 8), lit(STATE_FETCH, width: 8)),
          STATE_WRITE_MEM => lit(STATE_FETCH, width: 8),
          STATE_BRANCH => mux(branch_taken_val, lit(STATE_BRANCH_TAKE, width: 8), lit(STATE_FETCH, width: 8)),
          STATE_BRANCH_TAKE => lit(STATE_FETCH, width: 8),
          STATE_PUSH => lit(STATE_FETCH, width: 8),
          STATE_PULL => lit(STATE_EXECUTE, width: 8),
          STATE_JSR_PUSH_HI => lit(STATE_JSR_PUSH_LO, width: 8),
          STATE_JSR_PUSH_LO => lit(STATE_EXECUTE, width: 8),
          STATE_RTS_PULL_LO => lit(STATE_RTS_PULL_HI, width: 8),
          STATE_RTS_PULL_HI => lit(STATE_FETCH, width: 8),
          STATE_RTI_PULL_P => lit(STATE_RTI_PULL_LO, width: 8),
          STATE_RTI_PULL_LO => lit(STATE_RTI_PULL_HI, width: 8),
          STATE_RTI_PULL_HI => lit(STATE_FETCH, width: 8),
          STATE_BRK_PUSH_HI => lit(STATE_BRK_PUSH_LO, width: 8),
          STATE_BRK_PUSH_LO => lit(STATE_BRK_PUSH_P, width: 8),
          STATE_BRK_PUSH_P => lit(STATE_BRK_VEC_LO, width: 8),
          STATE_BRK_VEC_LO => lit(STATE_BRK_VEC_HI, width: 8),
          STATE_BRK_VEC_HI => lit(STATE_HALT, width: 8),
          STATE_HALT => lit(STATE_HALT, width: 8)
        }, default: STATE_FETCH),
        state)
    end

    # Control signal behavior blocks - combinational outputs based on state
    behavior do
      # state_before and state_pre are just the current state (for control signal alignment)
      state_before <= state
      state_pre <= state

      # halted: true when in HALT state
      halted <= (state == lit(STATE_HALT, width: 8))

      # mem_read: enabled in fetch, read states
      mem_read <= case_select(state, {
        STATE_RESET => lit(1, width: 1),
        STATE_FETCH => lit(1, width: 1),
        STATE_FETCH_OP1 => lit(1, width: 1),
        STATE_FETCH_OP2 => lit(1, width: 1),
        STATE_ADDR_LO => lit(1, width: 1),
        STATE_ADDR_HI => lit(1, width: 1),
        STATE_READ_MEM => lit(1, width: 1),
        STATE_PULL => lit(1, width: 1),
        STATE_RTS_PULL_LO => lit(1, width: 1),
        STATE_RTS_PULL_HI => lit(1, width: 1),
        STATE_RTI_PULL_P => lit(1, width: 1),
        STATE_RTI_PULL_LO => lit(1, width: 1),
        STATE_RTI_PULL_HI => lit(1, width: 1),
        STATE_BRK_VEC_LO => lit(1, width: 1),
        STATE_BRK_VEC_HI => lit(1, width: 1)
      }, default: 0)

      # mem_write: enabled in write states
      mem_write <= case_select(state, {
        STATE_WRITE_MEM => lit(1, width: 1),
        STATE_PUSH => lit(1, width: 1),
        STATE_JSR_PUSH_HI => lit(1, width: 1),
        STATE_JSR_PUSH_LO => lit(1, width: 1),
        STATE_BRK_PUSH_HI => lit(1, width: 1),
        STATE_BRK_PUSH_LO => lit(1, width: 1),
        STATE_BRK_PUSH_P => lit(1, width: 1)
      }, default: 0)

      # pc_inc: increment PC during fetch stages
      pc_inc <= case_select(state, {
        STATE_FETCH => lit(1, width: 1),
        STATE_FETCH_OP1 => lit(1, width: 1),
        STATE_FETCH_OP2 => lit(1, width: 1),
        STATE_RTS_PULL_HI => lit(1, width: 1)
      }, default: 0)

      # load_opcode: load IR during fetch
      load_opcode <= (state == lit(STATE_FETCH, width: 8))

      # load_operand_lo: load low operand byte
      load_operand_lo <= (state == lit(STATE_FETCH_OP1, width: 8))

      # load_operand_hi: load high operand byte
      load_operand_hi <= (state == lit(STATE_FETCH_OP2, width: 8))

      # load_addr_lo: load address latch low byte
      load_addr_lo <= case_select(state, {
        STATE_ADDR_LO => lit(1, width: 1),
        STATE_RTS_PULL_LO => lit(1, width: 1),
        STATE_RTI_PULL_LO => lit(1, width: 1),
        STATE_BRK_VEC_LO => lit(1, width: 1)
      }, default: 0)

      # load_addr_hi: load address latch high byte
      # NOTE: Only STATE_ADDR_HI should set this - for indirect addressing modes
      # RTS/RTI/BRK use return_addr = cat(data_in, alatch_addr_lo) directly,
      # so we must NOT corrupt addr_hi with stack/vector data here
      load_addr_hi <= case_select(state, {
        STATE_ADDR_HI => lit(1, width: 1)
      }, default: 0)

      # load_data: load data latch
      load_data <= case_select(state, {
        STATE_READ_MEM => lit(1, width: 1),
        STATE_PULL => lit(1, width: 1)
      }, default: 0)

      # alu_enable: enable ALU during execute
      alu_enable <= (state == lit(STATE_EXECUTE, width: 8))

      # sp_inc: increment stack pointer
      sp_inc <= case_select(state, {
        STATE_PULL => lit(1, width: 1),
        STATE_RTS_PULL_LO => lit(1, width: 1),
        STATE_RTS_PULL_HI => lit(1, width: 1),
        STATE_RTI_PULL_P => lit(1, width: 1),
        STATE_RTI_PULL_LO => lit(1, width: 1),
        STATE_RTI_PULL_HI => lit(1, width: 1)
      }, default: 0)

      # sp_dec: decrement stack pointer
      sp_dec <= case_select(state, {
        STATE_PUSH => lit(1, width: 1),
        STATE_JSR_PUSH_HI => lit(1, width: 1),
        STATE_JSR_PUSH_LO => lit(1, width: 1),
        STATE_BRK_PUSH_HI => lit(1, width: 1),
        STATE_BRK_PUSH_LO => lit(1, width: 1),
        STATE_BRK_PUSH_P => lit(1, width: 1)
      }, default: 0)

      # addr_sel: address source select
      addr_sel <= case_select(state, {
        STATE_RESET => lit(1, width: 3),
        STATE_ADDR_LO => lit(2, width: 3),
        STATE_ADDR_HI => lit(3, width: 3),
        STATE_READ_MEM => lit(4, width: 3),
        STATE_WRITE_MEM => lit(4, width: 3),
        STATE_PUSH => lit(5, width: 3),
        STATE_PULL => lit(6, width: 3),
        STATE_JSR_PUSH_HI => lit(5, width: 3),
        STATE_JSR_PUSH_LO => lit(5, width: 3),
        STATE_RTS_PULL_LO => lit(6, width: 3),
        STATE_RTS_PULL_HI => lit(6, width: 3),
        STATE_RTI_PULL_P => lit(6, width: 3),
        STATE_RTI_PULL_LO => lit(6, width: 3),
        STATE_RTI_PULL_HI => lit(6, width: 3),
        STATE_BRK_PUSH_HI => lit(5, width: 3),
        STATE_BRK_PUSH_LO => lit(5, width: 3),
        STATE_BRK_PUSH_P => lit(5, width: 3),
        STATE_BRK_VEC_LO => lit(7, width: 3),
        STATE_BRK_VEC_HI => lit(7, width: 3)
      }, default: 0)

      # data_sel: data source select - depends on state and is_status_op
      data_sel <= case_select(state, {
        STATE_WRITE_MEM => lit(1, width: 3),
        STATE_PUSH => mux(is_status_op, lit(4, width: 3), lit(0, width: 3)),
        STATE_JSR_PUSH_HI => lit(2, width: 3),
        STATE_JSR_PUSH_LO => lit(3, width: 3),
        STATE_BRK_PUSH_HI => lit(2, width: 3),
        STATE_BRK_PUSH_LO => lit(3, width: 3),
        STATE_BRK_PUSH_P => lit(4, width: 3)
      }, default: 0)

      # update_flags: update status flags
      # Set one cycle early so flags update on clock edge entering EXECUTE
      # Also for RTI_PULL_P (restores flags from stack)
      # States that transition to EXECUTE and may update flags:
      # - READ_MEM → EXECUTE
      # - PULL → EXECUTE
      # - DECODE → EXECUTE (implied/accumulator modes)
      # - FETCH_OP1 → EXECUTE (immediate mode)
      # - RTI_PULL_P (special: restores flags from stack)
      update_flags <= case_select(state, {
        STATE_READ_MEM => lit(1, width: 1),
        STATE_PULL => lit(1, width: 1),
        STATE_DECODE => mux((addr_mode == lit(MODE_IMPLIED, width: 4)) |
                            (addr_mode == lit(MODE_ACCUMULATOR, width: 4)),
                            lit(1, width: 1), lit(0, width: 1)),
        STATE_FETCH_OP1 => mux(addr_mode == lit(MODE_IMMEDIATE, width: 4),
                               lit(1, width: 1), lit(0, width: 1)),
        STATE_RTI_PULL_P => lit(1, width: 1)
      }, default: 0)

      # reg_write: write to register file
      # Set one cycle early (during state that transitions to EXECUTE) so registers
      # can capture on the clock edge that enters EXECUTE state
      # States that transition to EXECUTE:
      # - READ_MEM (memory read complete)
      # - PULL (stack pull complete)
      # - JSR_PUSH_LO (JSR about to jump)
      # - DECODE with implied/accumulator mode for ALU-like ops
      # - FETCH_OP1 with immediate mode (for LDA/LDX/LDY #imm, ADC/SBC #imm, etc.)
      next_is_execute = (state == lit(STATE_READ_MEM, width: 8)) |
                        (state == lit(STATE_PULL, width: 8)) |
                        (state == lit(STATE_JSR_PUSH_LO, width: 8)) |
                        ((state == lit(STATE_DECODE, width: 8)) &
                         ((instr_type == lit(TYPE_ALU, width: 4)) |
                          (instr_type == lit(TYPE_INC_DEC, width: 4)) |
                          (instr_type == lit(TYPE_SHIFT, width: 4)) |
                          (instr_type == lit(TYPE_TRANSFER, width: 4)) |
                          (instr_type == lit(TYPE_FLAG, width: 4))) &
                         ((addr_mode == lit(MODE_IMPLIED, width: 4)) |
                          (addr_mode == lit(MODE_ACCUMULATOR, width: 4)))) |
                        ((state == lit(STATE_FETCH_OP1, width: 8)) &
                         (addr_mode == lit(MODE_IMMEDIATE, width: 4)))
      reg_write <= mux(next_is_execute, writes_reg, lit(0, width: 1))

      # done: instruction complete when transitioning back to fetch
      done <= (state == lit(STATE_FETCH, width: 8))

      # pc_load: load PC during jumps and branches
      pc_load <= case_select(state, {
        STATE_BRANCH_TAKE => lit(1, width: 1),
        STATE_RTS_PULL_HI => lit(1, width: 1),
        STATE_RTI_PULL_HI => lit(1, width: 1),
        STATE_BRK_VEC_HI => lit(1, width: 1),
        STATE_EXECUTE => mux(instr_type == lit(TYPE_JUMP, width: 4), lit(1, width: 1), lit(0, width: 1))
      }, default: 0)
    end

    # Test helper accessors (use DSL state management)
    def current_state; read_reg(:state) || STATE_RESET; end
    def set_state(s); write_reg(:state, s); end

    # Generate synthesizable Verilog
    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Control Unit - Synthesizable Verilog
        // State machine that sequences instruction execution
        module mos6502_control_unit (
          input         clk,
          input         rst,
          input         rdy,

          // Decoded instruction info
          input  [3:0]  addr_mode,
          input  [3:0]  instr_type,
          input  [2:0]  branch_cond,
          input         is_read,
          input         is_write,
          input         is_rmw,
          input         writes_reg,
          input         is_status_op,

          // Status flags for branch decisions
          input         flag_n,
          input         flag_v,
          input         flag_z,
          input         flag_c,

          // Page crossing
          input         page_cross,

          // Memory ready
          input         mem_ready,

          // Control outputs
          output reg [7:0]  state,
          output reg [7:0]  state_before,
          output reg [7:0]  state_pre,
          output reg        pc_inc,
          output reg        pc_load,
          output reg        load_opcode,
          output reg        load_operand_lo,
          output reg        load_operand_hi,
          output reg        load_addr_lo,
          output reg        load_addr_hi,
          output reg        load_data,
          output reg        mem_read,
          output reg        mem_write,
          output reg [2:0]  addr_sel,
          output reg [2:0]  data_sel,
          output reg        alu_enable,
          output reg        reg_write,
          output reg        sp_inc,
          output reg        sp_dec,
          output reg        update_flags,
          output reg        done,
          output reg        halted,
          output reg [31:0] cycle_count
        );

          // State constants
          localparam STATE_RESET       = 8'h00;
          localparam STATE_FETCH       = 8'h01;
          localparam STATE_DECODE      = 8'h02;
          localparam STATE_FETCH_OP1   = 8'h03;
          localparam STATE_FETCH_OP2   = 8'h04;
          localparam STATE_ADDR_LO     = 8'h05;
          localparam STATE_ADDR_HI     = 8'h06;
          localparam STATE_READ_MEM    = 8'h07;
          localparam STATE_EXECUTE     = 8'h08;
          localparam STATE_WRITE_MEM   = 8'h09;
          localparam STATE_PUSH        = 8'h0A;
          localparam STATE_PULL        = 8'h0B;
          localparam STATE_BRANCH      = 8'h0C;
          localparam STATE_BRANCH_TAKE = 8'h0D;
          localparam STATE_JSR_PUSH_HI = 8'h0E;
          localparam STATE_JSR_PUSH_LO = 8'h0F;
          localparam STATE_RTS_PULL_LO = 8'h10;
          localparam STATE_RTS_PULL_HI = 8'h11;
          localparam STATE_RTI_PULL_P  = 8'h12;
          localparam STATE_RTI_PULL_LO = 8'h13;
          localparam STATE_RTI_PULL_HI = 8'h14;
          localparam STATE_BRK_PUSH_HI = 8'h15;
          localparam STATE_BRK_PUSH_LO = 8'h16;
          localparam STATE_BRK_PUSH_P  = 8'h17;
          localparam STATE_BRK_VEC_LO  = 8'h18;
          localparam STATE_BRK_VEC_HI  = 8'h19;
          localparam STATE_HALT        = 8'hFF;

          // Instruction type constants
          localparam TYPE_ALU       = 4'h0;
          localparam TYPE_LOAD      = 4'h1;
          localparam TYPE_STORE     = 4'h2;
          localparam TYPE_TRANSFER  = 4'h3;
          localparam TYPE_INC_DEC   = 4'h4;
          localparam TYPE_SHIFT     = 4'h5;
          localparam TYPE_BRANCH    = 4'h6;
          localparam TYPE_JUMP      = 4'h7;
          localparam TYPE_STACK     = 4'h8;
          localparam TYPE_FLAG      = 4'h9;
          localparam TYPE_NOP       = 4'hA;
          localparam TYPE_BRK       = 4'hB;

          // Addressing mode constants
          localparam MODE_IMPLIED     = 4'h0;
          localparam MODE_ACCUMULATOR = 4'h1;
          localparam MODE_IMMEDIATE   = 4'h2;
          localparam MODE_ZERO_PAGE   = 4'h3;
          localparam MODE_ZERO_PAGE_X = 4'h4;
          localparam MODE_ZERO_PAGE_Y = 4'h5;
          localparam MODE_ABSOLUTE    = 4'h6;
          localparam MODE_ABSOLUTE_X  = 4'h7;
          localparam MODE_ABSOLUTE_Y  = 4'h8;
          localparam MODE_INDIRECT    = 4'h9;
          localparam MODE_INDEXED_IND = 4'hA;
          localparam MODE_INDIRECT_IDX = 4'hB;
          localparam MODE_RELATIVE    = 4'hC;
          localparam MODE_STACK       = 4'hD;

          // Branch condition constants
          localparam BRANCH_BPL = 3'd0;
          localparam BRANCH_BMI = 3'd1;
          localparam BRANCH_BVC = 3'd2;
          localparam BRANCH_BVS = 3'd3;
          localparam BRANCH_BCC = 3'd4;
          localparam BRANCH_BCS = 3'd5;
          localparam BRANCH_BNE = 3'd6;
          localparam BRANCH_BEQ = 3'd7;

          // Internal registers
          reg [7:0] current_state;
          reg [2:0] reset_step;

          // Branch taken logic
          wire branch_taken;
          assign branch_taken =
            (branch_cond == BRANCH_BPL) ? ~flag_n :
            (branch_cond == BRANCH_BMI) ? flag_n :
            (branch_cond == BRANCH_BVC) ? ~flag_v :
            (branch_cond == BRANCH_BVS) ? flag_v :
            (branch_cond == BRANCH_BCC) ? ~flag_c :
            (branch_cond == BRANCH_BCS) ? flag_c :
            (branch_cond == BRANCH_BNE) ? ~flag_z :
            (branch_cond == BRANCH_BEQ) ? flag_z : 1'b0;

          // Needs memory read
          wire needs_read;
          assign needs_read = is_read | is_rmw;

          // Next state after decode
          wire [7:0] decode_next_state;
          assign decode_next_state =
            ((instr_type == TYPE_ALU) || (instr_type == TYPE_LOAD) ||
             (instr_type == TYPE_STORE) || (instr_type == TYPE_INC_DEC) ||
             (instr_type == TYPE_SHIFT)) ?
              ((addr_mode == MODE_IMPLIED) || (addr_mode == MODE_ACCUMULATOR)) ? STATE_EXECUTE : STATE_FETCH_OP1 :
            ((instr_type == TYPE_TRANSFER) || (instr_type == TYPE_FLAG) || (instr_type == TYPE_NOP)) ?
              STATE_EXECUTE :
            (instr_type == TYPE_BRANCH) ?
              STATE_FETCH_OP1 :
            (instr_type == TYPE_JUMP) ?
              (addr_mode == MODE_IMPLIED) ? STATE_RTS_PULL_LO :
              ((addr_mode == MODE_ABSOLUTE) || (addr_mode == MODE_INDIRECT)) ? STATE_FETCH_OP1 : STATE_FETCH :
            (instr_type == TYPE_STACK) ?
              is_write ? STATE_PUSH : STATE_PULL :
            (instr_type == TYPE_BRK) ?
              STATE_BRK_PUSH_HI :
              STATE_FETCH;

          // Next state after fetch_op1
          wire [7:0] fetch_op1_next_state;
          assign fetch_op1_next_state =
            (addr_mode == MODE_IMMEDIATE) ? STATE_EXECUTE :
            ((addr_mode == MODE_ZERO_PAGE) || (addr_mode == MODE_ZERO_PAGE_X) || (addr_mode == MODE_ZERO_PAGE_Y)) ?
              needs_read ? STATE_READ_MEM :
              is_write ? STATE_WRITE_MEM : STATE_EXECUTE :
            (addr_mode == MODE_RELATIVE) ? STATE_BRANCH :
            ((addr_mode == MODE_INDEXED_IND) || (addr_mode == MODE_INDIRECT_IDX)) ? STATE_ADDR_LO :
              STATE_FETCH_OP2;

          // Next state after fetch_op2
          wire [7:0] fetch_op2_next_state;
          assign fetch_op2_next_state =
            (addr_mode == MODE_INDIRECT) ? STATE_ADDR_LO :
            ((instr_type == TYPE_JUMP) && is_write) ? STATE_JSR_PUSH_HI :
            needs_read ? STATE_READ_MEM :
            is_write ? STATE_WRITE_MEM : STATE_EXECUTE;

          // Next state after addr_hi
          wire [7:0] addr_hi_next_state;
          assign addr_hi_next_state =
            (addr_mode == MODE_INDIRECT) ? STATE_EXECUTE :
            needs_read ? STATE_READ_MEM :
            is_write ? STATE_WRITE_MEM : STATE_EXECUTE;

          // State register
          always @(posedge clk or posedge rst) begin
            if (rst) begin
              current_state <= STATE_RESET;
              reset_step <= 3'd0;
              cycle_count <= 32'd0;
              state_pre <= STATE_RESET;
              state_before <= STATE_RESET;
            end else if (rdy) begin
              cycle_count <= cycle_count + 32'd1;
              state_pre <= current_state;
              state_before <= current_state;

              case (current_state)
                STATE_RESET: begin
                  reset_step <= reset_step + 3'd1;
                  if (reset_step >= 3'd5)
                    current_state <= STATE_FETCH;
                end
                STATE_FETCH: current_state <= STATE_DECODE;
                STATE_DECODE: current_state <= decode_next_state;
                STATE_FETCH_OP1: current_state <= fetch_op1_next_state;
                STATE_FETCH_OP2: current_state <= fetch_op2_next_state;
                STATE_ADDR_LO: current_state <= STATE_ADDR_HI;
                STATE_ADDR_HI: current_state <= addr_hi_next_state;
                STATE_READ_MEM: current_state <= STATE_EXECUTE;
                STATE_EXECUTE: current_state <= is_rmw ? STATE_WRITE_MEM : STATE_FETCH;
                STATE_WRITE_MEM: current_state <= STATE_FETCH;
                STATE_BRANCH: current_state <= branch_taken ? STATE_BRANCH_TAKE : STATE_FETCH;
                STATE_BRANCH_TAKE: current_state <= STATE_FETCH;
                STATE_PUSH: current_state <= STATE_FETCH;
                STATE_PULL: current_state <= STATE_EXECUTE;
                STATE_JSR_PUSH_HI: current_state <= STATE_JSR_PUSH_LO;
                STATE_JSR_PUSH_LO: current_state <= STATE_EXECUTE;
                STATE_RTS_PULL_LO: current_state <= STATE_RTS_PULL_HI;
                STATE_RTS_PULL_HI: current_state <= STATE_FETCH;
                STATE_RTI_PULL_P: current_state <= STATE_RTI_PULL_LO;
                STATE_RTI_PULL_LO: current_state <= STATE_RTI_PULL_HI;
                STATE_RTI_PULL_HI: current_state <= STATE_FETCH;
                STATE_BRK_PUSH_HI: current_state <= STATE_BRK_PUSH_LO;
                STATE_BRK_PUSH_LO: current_state <= STATE_BRK_PUSH_P;
                STATE_BRK_PUSH_P: current_state <= STATE_BRK_VEC_LO;
                STATE_BRK_VEC_LO: current_state <= STATE_BRK_VEC_HI;
                STATE_BRK_VEC_HI: current_state <= STATE_HALT;
                STATE_HALT: current_state <= STATE_HALT;
                default: current_state <= STATE_FETCH;
              endcase
            end
          end

          // Control signal output (combinational)
          always @* begin
            // Default all outputs to 0
            state = current_state;
            pc_inc = 1'b0;
            pc_load = 1'b0;
            load_opcode = 1'b0;
            load_operand_lo = 1'b0;
            load_operand_hi = 1'b0;
            load_addr_lo = 1'b0;
            load_addr_hi = 1'b0;
            load_data = 1'b0;
            mem_read = 1'b0;
            mem_write = 1'b0;
            addr_sel = 3'd0;
            data_sel = 3'd0;
            alu_enable = 1'b0;
            reg_write = 1'b0;
            sp_inc = 1'b0;
            sp_dec = 1'b0;
            update_flags = 1'b0;
            done = 1'b0;
            halted = (current_state == STATE_HALT);

            case (current_state)
              STATE_RESET: begin
                mem_read = 1'b1;
                addr_sel = 3'd1;
              end

              STATE_FETCH: begin
                mem_read = 1'b1;
                load_opcode = 1'b1;
                pc_inc = 1'b1;
              end

              STATE_DECODE: begin
                // Decode happens combinationally
              end

              STATE_FETCH_OP1: begin
                mem_read = 1'b1;
                load_operand_lo = 1'b1;
                pc_inc = 1'b1;
              end

              STATE_FETCH_OP2: begin
                mem_read = 1'b1;
                load_operand_hi = 1'b1;
                pc_inc = 1'b1;
              end

              STATE_ADDR_LO: begin
                mem_read = 1'b1;
                load_addr_lo = 1'b1;
                addr_sel = 3'd2;
              end

              STATE_ADDR_HI: begin
                mem_read = 1'b1;
                load_addr_hi = 1'b1;
                addr_sel = 3'd3;
              end

              STATE_READ_MEM: begin
                mem_read = 1'b1;
                load_data = 1'b1;
                addr_sel = 3'd4;
              end

              STATE_EXECUTE: begin
                alu_enable = 1'b1;
                reg_write = writes_reg;
                update_flags = 1'b1;
                if (instr_type == TYPE_JUMP)
                  pc_load = 1'b1;
                if (~is_rmw)
                  done = 1'b1;
              end

              STATE_WRITE_MEM: begin
                mem_write = 1'b1;
                addr_sel = 3'd4;
                data_sel = 3'd1;
                done = 1'b1;
              end

              STATE_BRANCH: begin
                // Check condition
              end

              STATE_BRANCH_TAKE: begin
                pc_load = 1'b1;
                done = 1'b1;
              end

              STATE_PUSH: begin
                mem_write = 1'b1;
                addr_sel = 3'd5;
                data_sel = is_status_op ? 3'd4 : 3'd0;
                sp_dec = 1'b1;
                done = 1'b1;
              end

              STATE_PULL: begin
                sp_inc = 1'b1;
                mem_read = 1'b1;
                addr_sel = 3'd6;
                load_data = 1'b1;
              end

              STATE_JSR_PUSH_HI: begin
                mem_write = 1'b1;
                addr_sel = 3'd5;
                data_sel = 3'd2;
                sp_dec = 1'b1;
              end

              STATE_JSR_PUSH_LO: begin
                mem_write = 1'b1;
                addr_sel = 3'd5;
                data_sel = 3'd3;
                sp_dec = 1'b1;
              end

              STATE_RTS_PULL_LO: begin
                sp_inc = 1'b1;
                mem_read = 1'b1;
                addr_sel = 3'd6;
                load_addr_lo = 1'b1;
              end

              STATE_RTS_PULL_HI: begin
                sp_inc = 1'b1;
                mem_read = 1'b1;
                addr_sel = 3'd6;
                load_addr_hi = 1'b1;
                pc_load = 1'b1;
                pc_inc = 1'b1;
                done = 1'b1;
              end

              STATE_RTI_PULL_P: begin
                sp_inc = 1'b1;
                mem_read = 1'b1;
                addr_sel = 3'd6;
                update_flags = 1'b1;
              end

              STATE_RTI_PULL_LO: begin
                sp_inc = 1'b1;
                mem_read = 1'b1;
                addr_sel = 3'd6;
                load_addr_lo = 1'b1;
              end

              STATE_RTI_PULL_HI: begin
                sp_inc = 1'b1;
                mem_read = 1'b1;
                addr_sel = 3'd6;
                load_addr_hi = 1'b1;
                pc_load = 1'b1;
                done = 1'b1;
              end

              STATE_BRK_PUSH_HI: begin
                mem_write = 1'b1;
                addr_sel = 3'd5;
                data_sel = 3'd2;
                sp_dec = 1'b1;
              end

              STATE_BRK_PUSH_LO: begin
                mem_write = 1'b1;
                addr_sel = 3'd5;
                data_sel = 3'd3;
                sp_dec = 1'b1;
              end

              STATE_BRK_PUSH_P: begin
                mem_write = 1'b1;
                addr_sel = 3'd5;
                data_sel = 3'd4;
                sp_dec = 1'b1;
              end

              STATE_BRK_VEC_LO: begin
                mem_read = 1'b1;
                addr_sel = 3'd7;
                load_addr_lo = 1'b1;
              end

              STATE_BRK_VEC_HI: begin
                mem_read = 1'b1;
                addr_sel = 3'd7;
                load_addr_hi = 1'b1;
                pc_load = 1'b1;
                done = 1'b1;
              end

              default: begin
                // Default state
              end
            endcase
          end

        endmodule
      VERILOG
    end

  end
end
