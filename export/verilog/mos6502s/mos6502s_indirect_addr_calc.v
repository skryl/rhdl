module mos6502s_indirect_addr_calc(
  input [3:0] mode,
  input [7:0] operand_lo,
  input [7:0] operand_hi,
  input [7:0] x_reg,
  output [15:0] ptr_addr_lo,
  output [15:0] ptr_addr_hi
);

  wire [15:0] abs_addr;
  wire [7:0] zp_addr_x;
  wire [15:0] ind_hi_normal;
  wire [15:0] ind_hi_buggy;

  assign abs_addr = {operand_hi, operand_lo};
  assign zp_addr_x = (operand_lo + x_reg)[7:0];
  assign ind_hi_normal = ((abs_addr + 16'd1) & 17'd65535);
  assign ind_hi_buggy = {operand_hi, 8'd0};
  assign ptr_addr_lo = ((mode == 4'd9) ? abs_addr : ((mode == 4'd10) ? {8'd0, zp_addr_x} : ((mode == 4'd11) ? {8'd0, operand_lo} : 1'b0)));
  assign ptr_addr_hi = ((mode == 4'd9) ? ((operand_lo == 8'd255) ? ind_hi_buggy : ind_hi_normal) : ((mode == 4'd10) ? {8'd0, (zp_addr_x + 8'd1)[7:0]} : ((mode == 4'd11) ? {8'd0, (operand_lo + 8'd1)[7:0]} : 1'b0)));

endmodule