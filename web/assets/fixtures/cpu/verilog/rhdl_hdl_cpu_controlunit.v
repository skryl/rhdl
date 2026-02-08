module cpu_control_unit(
  input clk,
  input rst,
  input [1:0] instr_length,
  input is_halt,
  input is_call,
  input is_ret,
  input is_branch,
  input is_jump,
  input is_lda,
  input is_reg_write,
  input is_mem_write,
  input is_mem_read,
  input is_sta_indirect,
  input is_lda_indirect,
  input [1:0] pc_src,
  input alu_src,
  input sp_empty,
  input sp_full,
  output reg [7:0] state,
  output [3:0] mem_addr_sel,
  output mem_read_en,
  output mem_write_en,
  output instr_latch_en,
  output operand_lo_latch_en,
  output operand_hi_latch_en,
  output acc_load_en,
  output zero_flag_load_en,
  output pc_load_en,
  output pc_inc_en,
  output sp_push_en,
  output sp_pop_en,
  output [1:0] data_out_sel,
  output halted,
  output done,
  output mem_data_latch_en,
  output indirect_hi_latch_en,
  output indirect_lo_latch_en
);


  initial begin
    state = 8'd0;
  end

  assign mem_addr_sel = ((state == 8'd1) ? 4'd0 : ((state == 8'd3) ? 4'd1 : ((state == 8'd4) ? 4'd2 : ((state == 8'd5) ? 4'd3 : ((state == 8'd7) ? 4'd3 : ((state == 8'd8) ? 4'd5 : ((state == 8'd9) ? 4'd6 : ((state == 8'd10) ? 4'd7 : ((state == 8'd11) ? 4'd8 : ((state == 8'd12) ? 4'd9 : ((state == 8'd13) ? 4'd9 : 1'b0)))))))))));
  assign mem_read_en = ((state == 8'd1) ? 1'b1 : ((state == 8'd3) ? 1'b1 : ((state == 8'd4) ? 1'b1 : ((state == 8'd5) ? 1'b1 : ((state == 8'd9) ? 1'b1 : ((state == 8'd10) ? 1'b1 : ((state == 8'd11) ? 1'b1 : ((state == 8'd13) ? 1'b1 : 1'b0))))))));
  assign mem_write_en = ((state == 8'd7) ? 1'b1 : ((state == 8'd8) ? 1'b1 : ((state == 8'd12) ? 1'b1 : 1'b0)));
  assign instr_latch_en = (state == 8'd1);
  assign operand_lo_latch_en = (state == 8'd3);
  assign operand_hi_latch_en = (state == 8'd4);
  assign acc_load_en = ((state == 8'd6) ? is_reg_write : 1'b0);
  assign zero_flag_load_en = ((state == 8'd6) ? is_reg_write : 1'b0);
  assign pc_inc_en = ((state == 8'd2) ? (((instr_length == 2'd1) & ~((((is_call | is_branch) | is_jump) | is_halt) | (is_ret & sp_empty))) ? 1'b1 : 1'b0) : ((state == 8'd3) ? (((instr_length == 2'd2) & ~((((is_call | is_branch) | is_jump) | is_halt) | (is_ret & sp_empty))) ? 1'b1 : 1'b0) : ((state == 8'd4) ? (~((((is_call | is_branch) | is_jump) | is_halt) | (is_ret & sp_empty)) ? 1'b1 : 1'b0) : 1'b0)));
  assign pc_load_en = ((state == 8'd6) ? ((is_branch | is_jump) | is_call) : 1'b0);
  assign sp_push_en = (state == 8'd8);
  assign sp_pop_en = (state == 8'd9);
  assign data_out_sel = {{1{1'b0}}, ((state == 8'd8) ? 1'b1 : 1'b0)};
  assign halted = (state == 8'd255);
  assign done = ((state == 8'd6) ? 1'b1 : ((state == 8'd7) ? 1'b1 : 1'b0));
  assign mem_data_latch_en = (((state == 8'd5) | (state == 8'd9)) | (state == 8'd13));
  assign indirect_hi_latch_en = (state == 8'd10);
  assign indirect_lo_latch_en = (state == 8'd11);

  always @(posedge clk) begin
  if (rst) begin
    state <= 8'd0;
  end
  else begin
    state <= ((state == 8'd0)) ? 8'd1 : ((state == 8'd1)) ? 8'd2 : ((state == 8'd2)) ? (is_halt ? 8'd255 : ((instr_length == 2'd1) ? (is_call ? (sp_full ? 8'd255 : 8'd8) : (is_ret ? (sp_empty ? 8'd255 : 8'd9) : (is_mem_read ? 8'd5 : (is_mem_write ? 8'd7 : 8'd6)))) : 8'd3)) : ((state == 8'd3)) ? ((instr_length == 2'd3) ? 8'd4 : (is_call ? (sp_full ? 8'd255 : 8'd8) : (is_mem_read ? 8'd5 : (is_mem_write ? 8'd7 : (alu_src ? 8'd6 : 8'd5))))) : ((state == 8'd4)) ? ((is_sta_indirect | is_lda_indirect) ? 8'd10 : (is_call ? (sp_full ? 8'd255 : 8'd8) : (is_mem_write ? 8'd7 : 8'd6))) : ((state == 8'd5)) ? 8'd6 : ((state == 8'd6)) ? 8'd1 : ((state == 8'd7)) ? 8'd1 : ((state == 8'd8)) ? 8'd6 : ((state == 8'd9)) ? 8'd6 : ((state == 8'd10)) ? 8'd11 : ((state == 8'd11)) ? (is_lda_indirect ? 8'd13 : 8'd12) : ((state == 8'd12)) ? 8'd1 : ((state == 8'd13)) ? 8'd6 : ((state == 8'd255)) ? 8'd255 : 8'd1;
  end
  end

endmodule