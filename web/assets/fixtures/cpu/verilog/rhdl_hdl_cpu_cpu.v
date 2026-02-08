module cpu_cpu(
  input clk,
  input rst,
  input [7:0] mem_data_in,
  output [7:0] mem_data_out,
  output [15:0] mem_addr,
  output mem_write_en,
  output mem_read_en,
  output [15:0] pc_out,
  output [7:0] acc_out,
  output [7:0] sp_out,
  output halted,
  output [7:0] state_out,
  output zero_flag_out
);

  reg ctrl_done;
  wire [7:0] instruction_reg;
  wire [3:0] operand_nibble;
  wire [7:0] operand_lo;
  wire [7:0] operand_hi;
  wire [15:0] operand_16;
  wire [7:0] effective_operand;
  wire [7:0] mem_data_latched;
  wire [7:0] indirect_hi;
  wire [7:0] indirect_lo;
  wire [15:0] indirect_addr;
  wire [7:0] alu_result;
  wire alu_zero;
  wire [7:0] alu_b_input;
  wire zero_flag_reg_out;
  wire zero_flag_next;
  wire [7:0] acc_result;
  wire [3:0] dec_alu_op;
  wire dec_alu_src;
  wire dec_reg_write;
  wire dec_mem_read;
  wire dec_mem_write;
  wire dec_branch;
  wire dec_jump;
  wire [1:0] dec_pc_src;
  wire dec_halt;
  wire dec_call;
  wire dec_ret;
  wire [1:0] dec_instr_length;
  wire dec_is_lda;
  wire dec_sta_indirect;
  wire dec_lda_indirect;
  wire [7:0] ctrl_state;
  wire [3:0] ctrl_mem_addr_sel;
  wire ctrl_mem_read_en;
  wire ctrl_mem_write_en;
  wire ctrl_instr_latch_en;
  wire ctrl_operand_lo_latch_en;
  wire ctrl_operand_hi_latch_en;
  wire ctrl_acc_load_en;
  wire ctrl_zero_flag_load_en;
  wire ctrl_pc_load_en;
  wire ctrl_pc_inc_en;
  wire ctrl_sp_push_en;
  wire ctrl_sp_pop_en;
  wire [1:0] ctrl_data_out_sel;
  wire ctrl_halted;
  wire ctrl_mem_data_latch_en;
  wire ctrl_indirect_hi_latch_en;
  wire ctrl_indirect_lo_latch_en;
  wire [15:0] pc_next;
  wire [15:0] pc_current;
  wire [7:0] return_addr;
  wire [7:0] acc_data_in;
  wire pc_update_en;

  assign operand_nibble = instruction_reg[3:0];
  assign effective_operand = ((dec_instr_length == 2'd1) ? operand_nibble : operand_lo);
  assign alu_b_input = mem_data_latched;
  assign operand_16 = {operand_lo, operand_hi};
  assign indirect_addr = {indirect_hi, indirect_lo};
  assign acc_data_in = (dec_alu_src ? operand_lo : mem_data_latched);
  assign pc_update_en = ((ctrl_pc_inc_en | ctrl_pc_load_en) | ((ctrl_state == 8'd6) & dec_ret));
  assign zero_flag_next = (dec_is_lda ? ((acc_data_in == 8'd0) ? 1'b1 : 1'b0) : alu_zero);
  assign mem_addr = (((ctrl_mem_addr_sel == 4'd0) ? pc_current : ((ctrl_mem_addr_sel == 4'd1) ? (pc_current + 16'd1) : ((ctrl_mem_addr_sel == 4'd2) ? (pc_current + 16'd2) : ((ctrl_mem_addr_sel == 4'd3) ? effective_operand : ((ctrl_mem_addr_sel == 4'd4) ? operand_16 : ((ctrl_mem_addr_sel == 4'd5) ? sp_out : ((ctrl_mem_addr_sel == 4'd6) ? (sp_out + 8'd1) : ((ctrl_mem_addr_sel == 4'd7) ? operand_lo : ((ctrl_mem_addr_sel == 4'd8) ? operand_hi : ((ctrl_mem_addr_sel == 4'd9) ? indirect_addr : pc_current)))))))))) & 17'd65535);
  assign mem_data_out = ((ctrl_data_out_sel == 2'd0) ? acc_out : return_addr);
  assign return_addr = ((pc_current + {{14{1'b0}}, dec_instr_length}) & 8'd255);
  assign pc_next = ((ctrl_pc_inc_en ? (pc_current + {{14{1'b0}}, dec_instr_length}) : (ctrl_pc_load_en ? ((dec_pc_src == 2'd0) ? (pc_current + {{14{1'b0}}, dec_instr_length}) : ((dec_pc_src == 2'd1) ? effective_operand : ((dec_pc_src == 2'd2) ? operand_16 : pc_current))) : (dec_ret ? mem_data_latched : pc_current))) & 17'd65535);
  assign pc_out = pc_current;
  assign halted = ctrl_halted;
  assign state_out = ctrl_state;
  assign mem_read_en = ctrl_mem_read_en;
  assign mem_write_en = ctrl_mem_write_en;
  assign zero_flag_out = zero_flag_reg_out;

  cpu_instruction_decoder decoder (
    .instruction(instruction_reg),
    .zero_flag(zero_flag_reg_out),
    .alu_op(decoder__alu_op),
    .alu_src(decoder__alu_src),
    .reg_write(decoder__reg_write),
    .mem_read(decoder__mem_read),
    .mem_write(decoder__mem_write),
    .branch(decoder__branch),
    .jump(decoder__jump),
    .pc_src(decoder__pc_src),
    .halt(decoder__halt),
    .call(decoder__call),
    .ret(decoder__ret),
    .instr_length(decoder__instr_length),
    .is_lda(decoder__is_lda),
    .sta_indirect(decoder__sta_indirect),
    .lda_indirect(decoder__lda_indirect)
  );

  cpu_control_unit ctrl (
    .clk(clk),
    .rst(rst),
    .instr_length(dec_instr_length),
    .is_halt(dec_halt),
    .is_call(dec_call),
    .is_ret(dec_ret),
    .is_branch(dec_branch),
    .is_jump(dec_jump),
    .is_lda(dec_is_lda),
    .is_reg_write(dec_reg_write),
    .is_mem_write(dec_mem_write),
    .is_mem_read(dec_mem_read),
    .is_sta_indirect(dec_sta_indirect),
    .is_lda_indirect(dec_lda_indirect),
    .pc_src(dec_pc_src),
    .alu_src(dec_alu_src),
    .sp_empty(__sp___empty_),
    .sp_full(__sp___full_),
    .state(ctrl__state),
    .mem_addr_sel(ctrl__mem_addr_sel),
    .mem_read_en(ctrl__mem_read_en),
    .mem_write_en(ctrl__mem_write_en),
    .instr_latch_en(ctrl__instr_latch_en),
    .operand_lo_latch_en(ctrl__operand_lo_latch_en),
    .operand_hi_latch_en(ctrl__operand_hi_latch_en),
    .acc_load_en(ctrl__acc_load_en),
    .zero_flag_load_en(ctrl__zero_flag_load_en),
    .pc_load_en(ctrl__pc_load_en),
    .pc_inc_en(ctrl__pc_inc_en),
    .sp_push_en(ctrl__sp_push_en),
    .sp_pop_en(ctrl__sp_pop_en),
    .data_out_sel(ctrl__data_out_sel),
    .halted(ctrl__halted),
    .mem_data_latch_en(ctrl__mem_data_latch_en),
    .indirect_hi_latch_en(ctrl__indirect_hi_latch_en),
    .indirect_lo_latch_en(ctrl__indirect_lo_latch_en)
  );

  alu #(.width(8)) alu (
    .a(acc_out),
    .b(alu_b_input),
    .op(dec_alu_op),
    .result(alu__result),
    .zero(alu__zero)
  );

  program_counter #(.width(16)) pc_reg (
    .clk(clk),
    .rst(rst),
    .d(pc_next),
    .load(pc_update_en),
    .q(pc_reg__q)
  );

  register #(.width(8)) acc (
    .clk(clk),
    .rst(rst),
    .d(acc_result),
    .en(ctrl_acc_load_en),
    .q(acc__q)
  );

  stack_pointer #(.width(8), .initial_rhdl(255)) sp (
    .clk(clk),
    .rst(rst),
    .push(ctrl_sp_push_en),
    .pop(ctrl_sp_pop_en),
    .q(sp__q)
  );

  d_flip_flop zero_flag_reg (
    .clk(clk),
    .rst(rst),
    .en(ctrl_zero_flag_load_en),
    .d(zero_flag_next),
    .q(zero_flag_reg__q)
  );

  mux2 #(.width(8)) acc_mux (
    .a(alu_result),
    .b(acc_data_in),
    .sel(dec_is_lda),
    .y(acc_mux__y)
  );

  register #(.width(8)) instr_reg (
    .clk(clk),
    .rst(rst),
    .d(mem_data_in),
    .en(ctrl_instr_latch_en),
    .q(instr_reg__q)
  );

  register #(.width(8)) op_lo_reg (
    .clk(clk),
    .rst(rst),
    .d(mem_data_in),
    .en(ctrl_operand_lo_latch_en),
    .q(op_lo_reg__q)
  );

  register #(.width(8)) op_hi_reg (
    .clk(clk),
    .rst(rst),
    .d(mem_data_in),
    .en(ctrl_operand_hi_latch_en),
    .q(op_hi_reg__q)
  );

  register #(.width(8)) mem_data_reg (
    .clk(clk),
    .rst(rst),
    .d(mem_data_in),
    .en(ctrl_mem_data_latch_en),
    .q(mem_data_reg__q)
  );

  register #(.width(8)) indirect_hi_reg (
    .clk(clk),
    .rst(rst),
    .d(mem_data_in),
    .en(ctrl_indirect_hi_latch_en),
    .q(indirect_hi_reg__q)
  );

  register #(.width(8)) indirect_lo_reg (
    .clk(clk),
    .rst(rst),
    .d(mem_data_in),
    .en(ctrl_indirect_lo_latch_en),
    .q(indirect_lo_reg__q)
  );

endmodule