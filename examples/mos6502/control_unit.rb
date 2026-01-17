# MOS 6502 Control Unit - Synthesizable DSL Version
# State machine that sequences instruction execution
# Sequential - requires always @(posedge clk) for synthesis

require_relative '../../lib/rhdl'

module MOS6502
  class ControlUnit < RHDL::HDL::SequentialComponent
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

    port_input :clk
    port_input :rst
    port_input :rdy            # Ready signal (for single-stepping)

    # Decoded instruction info
    port_input :addr_mode, width: 4
    port_input :instr_type, width: 4
    port_input :branch_cond, width: 3
    port_input :is_read
    port_input :is_write
    port_input :is_rmw
    port_input :writes_reg             # Instruction writes to register
    port_input :is_status_op           # Stack operation on status register (PHP/PLP)

    # Status flags for branch decisions
    port_input :flag_n
    port_input :flag_v
    port_input :flag_z
    port_input :flag_c

    # Page crossing
    port_input :page_cross

    # Memory ready
    port_input :mem_ready

    # Control outputs
    port_output :state, width: 8         # Current state
    port_output :state_before, width: 8  # State before transition (for control alignment)
    port_output :state_pre, width: 8     # State before transition (alias for state_before)
    port_output :pc_inc                  # Increment program counter
    port_output :pc_load                 # Load program counter
    port_output :load_opcode             # Load instruction register
    port_output :load_operand_lo         # Load operand low byte
    port_output :load_operand_hi         # Load operand high byte
    port_output :load_addr_lo            # Load address latch low
    port_output :load_addr_hi            # Load address latch high
    port_output :load_data               # Load data latch
    port_output :mem_read                # Memory read enable
    port_output :mem_write               # Memory write enable
    port_output :addr_sel, width: 3      # Address source select
    port_output :data_sel, width: 3      # Data source select
    port_output :alu_enable              # Enable ALU operation
    port_output :reg_write               # Write to register file
    port_output :sp_inc                  # Increment stack pointer
    port_output :sp_dec                  # Decrement stack pointer
    port_output :update_flags            # Update status flags
    port_output :done                    # Instruction complete
    port_output :halted                  # CPU halted
    port_output :cycle_count, width: 32  # Total cycles executed

    def initialize(name = nil)
      @state = STATE_RESET
      @reset_step = 0
      @cycle_count = 0
      super(name)
    end

    # Synthesizable propagate - all logic maps to Verilog
    def propagate
      current_state = @state

      # Output control signals FIRST, based on current state
      output_control_signals

      # Output state BEFORE transition so it stays aligned with control outputs
      out_set(:state_before, @state)

      # Then advance state machine on rising edge
      if rising_edge?
        if in_val(:rst) == 1
          @state = STATE_RESET
          @reset_step = 0
          @cycle_count = 0
        elsif in_val(:rdy) == 1
          @cycle_count += 1
          execute_state_machine
        end
      end

      # Output state AFTER transition
      out_set(:state, @state)
      out_set(:state_pre, current_state)
      out_set(:cycle_count, @cycle_count)
    end

    private

    def execute_state_machine
      mode = in_val(:addr_mode) & 0x0F
      itype = in_val(:instr_type) & 0x0F
      is_rd = in_val(:is_read)
      is_wr = in_val(:is_write)
      is_rmw_op = in_val(:is_rmw)

      case @state
      when STATE_RESET
        @reset_step += 1
        @state = STATE_FETCH if @reset_step >= 6

      when STATE_FETCH
        @state = STATE_DECODE

      when STATE_DECODE
        @state = next_state_after_decode(itype, mode, is_wr)

      when STATE_FETCH_OP1
        @state = next_state_after_fetch_op1(mode, is_rd, is_wr, is_rmw_op)

      when STATE_FETCH_OP2
        @state = next_state_after_fetch_op2(mode, itype, is_rd, is_wr, is_rmw_op)

      when STATE_ADDR_LO
        @state = STATE_ADDR_HI

      when STATE_ADDR_HI
        @state = next_state_after_addr_hi(mode, is_rd, is_wr, is_rmw_op)

      when STATE_READ_MEM
        @state = STATE_EXECUTE

      when STATE_EXECUTE
        @state = (is_rmw_op == 1) ? STATE_WRITE_MEM : STATE_FETCH

      when STATE_WRITE_MEM
        @state = STATE_FETCH

      when STATE_BRANCH
        @state = branch_taken? ? STATE_BRANCH_TAKE : STATE_FETCH

      when STATE_BRANCH_TAKE
        @state = STATE_FETCH

      when STATE_PUSH
        @state = STATE_FETCH

      when STATE_PULL
        @state = STATE_EXECUTE

      when STATE_JSR_PUSH_HI
        @state = STATE_JSR_PUSH_LO

      when STATE_JSR_PUSH_LO
        @state = STATE_EXECUTE

      when STATE_RTS_PULL_LO
        @state = STATE_RTS_PULL_HI

      when STATE_RTS_PULL_HI
        @state = STATE_FETCH

      when STATE_RTI_PULL_P
        @state = STATE_RTI_PULL_LO

      when STATE_RTI_PULL_LO
        @state = STATE_RTI_PULL_HI

      when STATE_RTI_PULL_HI
        @state = STATE_FETCH

      when STATE_BRK_PUSH_HI
        @state = STATE_BRK_PUSH_LO

      when STATE_BRK_PUSH_LO
        @state = STATE_BRK_PUSH_P

      when STATE_BRK_PUSH_P
        @state = STATE_BRK_VEC_LO

      when STATE_BRK_VEC_LO
        @state = STATE_BRK_VEC_HI

      when STATE_BRK_VEC_HI
        @state = STATE_HALT

      when STATE_HALT
        # Stay halted
      end
    end

    def next_state_after_decode(itype, mode, is_wr)
      case itype
      when TYPE_ALU, TYPE_LOAD, TYPE_STORE, TYPE_INC_DEC, TYPE_SHIFT
        if mode == MODE_IMPLIED || mode == MODE_ACCUMULATOR
          STATE_EXECUTE
        else
          STATE_FETCH_OP1
        end
      when TYPE_TRANSFER, TYPE_FLAG, TYPE_NOP
        STATE_EXECUTE
      when TYPE_BRANCH
        STATE_FETCH_OP1
      when TYPE_JUMP
        next_state_for_jump_decode(mode)
      when TYPE_STACK
        (is_wr == 1) ? STATE_PUSH : STATE_PULL
      when TYPE_BRK
        STATE_BRK_PUSH_HI
      else
        STATE_FETCH
      end
    end

    def next_state_for_jump_decode(mode)
      case mode
      when MODE_IMPLIED
        STATE_RTS_PULL_LO
      when MODE_ABSOLUTE, MODE_INDIRECT
        STATE_FETCH_OP1
      else
        STATE_FETCH
      end
    end

    def next_state_after_fetch_op1(mode, is_rd, is_wr, is_rmw_op)
      needs_read = (is_rd == 1) || (is_rmw_op == 1)

      case mode
      when MODE_IMMEDIATE
        STATE_EXECUTE
      when MODE_ZERO_PAGE, MODE_ZERO_PAGE_X, MODE_ZERO_PAGE_Y
        if needs_read
          STATE_READ_MEM
        elsif is_wr == 1
          STATE_WRITE_MEM
        else
          STATE_EXECUTE
        end
      when MODE_RELATIVE
        STATE_BRANCH
      when MODE_INDEXED_IND, MODE_INDIRECT_IDX
        STATE_ADDR_LO
      else
        STATE_FETCH_OP2
      end
    end

    def next_state_after_fetch_op2(mode, itype, is_rd, is_wr, is_rmw_op)
      needs_read = (is_rd == 1) || (is_rmw_op == 1)

      if mode == MODE_INDIRECT
        STATE_ADDR_LO
      elsif itype == TYPE_JUMP && is_wr == 1
        STATE_JSR_PUSH_HI
      elsif needs_read
        STATE_READ_MEM
      elsif is_wr == 1
        STATE_WRITE_MEM
      else
        STATE_EXECUTE
      end
    end

    def next_state_after_addr_hi(mode, is_rd, is_wr, is_rmw_op)
      needs_read = (is_rd == 1) || (is_rmw_op == 1)

      if mode == MODE_INDIRECT
        STATE_EXECUTE
      elsif needs_read
        STATE_READ_MEM
      elsif is_wr == 1
        STATE_WRITE_MEM
      else
        STATE_EXECUTE
      end
    end

    def branch_taken?
      cond = in_val(:branch_cond) & 0x07
      n = in_val(:flag_n)
      v = in_val(:flag_v)
      z = in_val(:flag_z)
      c = in_val(:flag_c)

      case cond
      when BRANCH_BPL then n == 0
      when BRANCH_BMI then n == 1
      when BRANCH_BVC then v == 0
      when BRANCH_BVS then v == 1
      when BRANCH_BCC then c == 0
      when BRANCH_BCS then c == 1
      when BRANCH_BNE then z == 0
      when BRANCH_BEQ then z == 1
      else false
      end
    end

    def output_control_signals
      # Default all outputs to 0
      out_set(:pc_inc, 0)
      out_set(:pc_load, 0)
      out_set(:load_opcode, 0)
      out_set(:load_operand_lo, 0)
      out_set(:load_operand_hi, 0)
      out_set(:load_addr_lo, 0)
      out_set(:load_addr_hi, 0)
      out_set(:load_data, 0)
      out_set(:mem_read, 0)
      out_set(:mem_write, 0)
      out_set(:addr_sel, 0)
      out_set(:data_sel, 0)
      out_set(:alu_enable, 0)
      out_set(:reg_write, 0)
      out_set(:sp_inc, 0)
      out_set(:sp_dec, 0)
      out_set(:update_flags, 0)
      out_set(:done, 0)
      out_set(:halted, (@state == STATE_HALT) ? 1 : 0)

      itype = in_val(:instr_type) & 0x0F
      is_rmw_op = in_val(:is_rmw)
      is_status = in_val(:is_status_op)
      writes_r = in_val(:writes_reg)

      case @state
      when STATE_RESET
        out_set(:mem_read, 1)
        out_set(:addr_sel, 1)

      when STATE_FETCH
        out_set(:mem_read, 1)
        out_set(:load_opcode, 1)
        out_set(:pc_inc, 1)

      when STATE_DECODE
        # Decode happens combinationally

      when STATE_FETCH_OP1
        out_set(:mem_read, 1)
        out_set(:load_operand_lo, 1)
        out_set(:pc_inc, 1)

      when STATE_FETCH_OP2
        out_set(:mem_read, 1)
        out_set(:load_operand_hi, 1)
        out_set(:pc_inc, 1)

      when STATE_ADDR_LO
        out_set(:mem_read, 1)
        out_set(:load_addr_lo, 1)
        out_set(:addr_sel, 2)

      when STATE_ADDR_HI
        out_set(:mem_read, 1)
        out_set(:load_addr_hi, 1)
        out_set(:addr_sel, 3)

      when STATE_READ_MEM
        out_set(:mem_read, 1)
        out_set(:load_data, 1)
        out_set(:addr_sel, 4)

      when STATE_EXECUTE
        out_set(:alu_enable, 1)
        out_set(:reg_write, writes_r)
        out_set(:update_flags, 1)
        out_set(:pc_load, 1) if itype == TYPE_JUMP
        out_set(:done, 1) unless is_rmw_op == 1

      when STATE_WRITE_MEM
        out_set(:mem_write, 1)
        out_set(:addr_sel, 4)
        out_set(:data_sel, 1)
        out_set(:done, 1)

      when STATE_BRANCH
        # Check condition - next state decision made in state machine

      when STATE_BRANCH_TAKE
        out_set(:pc_load, 1)
        out_set(:done, 1)

      when STATE_PUSH
        out_set(:mem_write, 1)
        out_set(:addr_sel, 5)
        out_set(:data_sel, (is_status == 1) ? 4 : 0)
        out_set(:sp_dec, 1)
        out_set(:done, 1)

      when STATE_PULL
        out_set(:sp_inc, 1)
        out_set(:mem_read, 1)
        out_set(:addr_sel, 6)
        out_set(:load_data, 1)

      when STATE_JSR_PUSH_HI
        out_set(:mem_write, 1)
        out_set(:addr_sel, 5)
        out_set(:data_sel, 2)
        out_set(:sp_dec, 1)

      when STATE_JSR_PUSH_LO
        out_set(:mem_write, 1)
        out_set(:addr_sel, 5)
        out_set(:data_sel, 3)
        out_set(:sp_dec, 1)

      when STATE_RTS_PULL_LO
        out_set(:sp_inc, 1)
        out_set(:mem_read, 1)
        out_set(:addr_sel, 6)
        out_set(:load_addr_lo, 1)

      when STATE_RTS_PULL_HI
        out_set(:sp_inc, 1)
        out_set(:mem_read, 1)
        out_set(:addr_sel, 6)
        out_set(:load_addr_hi, 1)
        out_set(:pc_load, 1)
        out_set(:pc_inc, 1)
        out_set(:done, 1)

      when STATE_RTI_PULL_P
        out_set(:sp_inc, 1)
        out_set(:mem_read, 1)
        out_set(:addr_sel, 6)
        out_set(:update_flags, 1)

      when STATE_RTI_PULL_LO
        out_set(:sp_inc, 1)
        out_set(:mem_read, 1)
        out_set(:addr_sel, 6)
        out_set(:load_addr_lo, 1)

      when STATE_RTI_PULL_HI
        out_set(:sp_inc, 1)
        out_set(:mem_read, 1)
        out_set(:addr_sel, 6)
        out_set(:load_addr_hi, 1)
        out_set(:pc_load, 1)
        out_set(:done, 1)

      when STATE_BRK_PUSH_HI
        out_set(:mem_write, 1)
        out_set(:addr_sel, 5)
        out_set(:data_sel, 2)
        out_set(:sp_dec, 1)

      when STATE_BRK_PUSH_LO
        out_set(:mem_write, 1)
        out_set(:addr_sel, 5)
        out_set(:data_sel, 3)
        out_set(:sp_dec, 1)

      when STATE_BRK_PUSH_P
        out_set(:mem_write, 1)
        out_set(:addr_sel, 5)
        out_set(:data_sel, 4)
        out_set(:sp_dec, 1)

      when STATE_BRK_VEC_LO
        out_set(:mem_read, 1)
        out_set(:addr_sel, 7)
        out_set(:load_addr_lo, 1)

      when STATE_BRK_VEC_HI
        out_set(:mem_read, 1)
        out_set(:addr_sel, 7)
        out_set(:load_addr_hi, 1)
        out_set(:pc_load, 1)
        out_set(:done, 1)
      end
    end

    public

    # Direct access for debugging
    def current_state
      @state
    end

    def set_state(s)
      @state = s
    end

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
