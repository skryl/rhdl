// MOS 6502 Control Unit - Synthesizable Verilog
// State machine that sequences instruction execution
module mos6502s_control_unit (
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
