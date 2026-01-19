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
      load_addr_hi <= case_select(state, {
        STATE_ADDR_HI => lit(1, width: 1),
        STATE_RTS_PULL_HI => lit(1, width: 1),
        STATE_RTI_PULL_HI => lit(1, width: 1),
        STATE_BRK_VEC_HI => lit(1, width: 1)
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

  end
end
