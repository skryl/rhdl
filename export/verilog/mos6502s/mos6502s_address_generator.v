module mos6502s_address_generator(
  input [3:0] mode,
  input [7:0] operand_lo,
  input [7:0] operand_hi,
  input [7:0] x_reg,
  input [7:0] y_reg,
  input [15:0] pc,
  input [7:0] sp,
  input [7:0] indirect_lo,
  input [7:0] indirect_hi,
  output [15:0] eff_addr,
  output page_cross,
  output is_zero_page
);

  wire [15:0] abs_addr;
  wire [15:0] abs_x_addr;
  wire [15:0] abs_y_addr;
  wire [15:0] ind_addr;
  wire [15:0] ind_y_addr;
  wire [15:0] rel_offset;
  wire [15:0] rel_addr;
  wire [15:0] stack_addr;

  assign abs_addr = {operand_hi, operand_lo};
  assign abs_x_addr = ((abs_addr + {8'd0, x_reg}) & 17'd65535);
  assign abs_y_addr = ((abs_addr + {8'd0, y_reg}) & 17'd65535);
  assign ind_addr = {indirect_hi, indirect_lo};
  assign ind_y_addr = ((ind_addr + {8'd0, y_reg}) & 17'd65535);
  assign rel_offset = (operand_lo[7] ? {8'd255, operand_lo} : {8'd0, operand_lo});
  assign rel_addr = ((pc + rel_offset) & 17'd65535);
  assign stack_addr = {8'd1, sp};
  assign eff_addr = ((mode == 4'd0) ? 16'd0 : ((mode == 4'd1) ? 16'd0 : ((mode == 4'd2) ? 16'd0 : ((mode == 4'd3) ? {8'd0, operand_lo} : ((mode == 4'd4) ? {8'd0, (operand_lo + x_reg)[7:0]} : ((mode == 4'd5) ? {8'd0, (operand_lo + y_reg)[7:0]} : ((mode == 4'd6) ? abs_addr : ((mode == 4'd7) ? abs_x_addr : ((mode == 4'd8) ? abs_y_addr : ((mode == 4'd9) ? ind_addr : ((mode == 4'd10) ? ind_addr : ((mode == 4'd11) ? ind_y_addr : ((mode == 4'd12) ? rel_addr : ((mode == 4'd13) ? stack_addr : 1'b0))))))))))))));
  assign page_cross = ((mode == 4'd7) ? (abs_x_addr[15:8] != operand_hi) : ((mode == 4'd8) ? (abs_y_addr[15:8] != operand_hi) : ((mode == 4'd11) ? (ind_y_addr[15:8] != indirect_hi) : ((mode == 4'd12) ? (rel_addr[15:8] != pc[15:8]) : 1'b0))));
  assign is_zero_page = ((mode == 4'd3) ? 1'b1 : ((mode == 4'd4) ? 1'b1 : ((mode == 4'd5) ? 1'b1 : 1'b0)));

endmodule