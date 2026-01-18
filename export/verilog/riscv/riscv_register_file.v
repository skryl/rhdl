module riscv_register_file(
  input clk,
  input rst,
  input [4:0] rs1_addr,
  input [4:0] rs2_addr,
  output [31:0] rs1_data,
  output [31:0] rs2_data,
  input [4:0] rd_addr,
  input [31:0] rd_data,
  input rd_we,
  output [31:0] debug_x1,
  output [31:0] debug_x2,
  output [31:0] debug_x10,
  output [31:0] debug_x11
);

  reg [31:0] regs [0:31];

  assign rs1_data = ((rs1_addr == 5'd0) ? 32'd0 : regs[rs1_addr]);
  assign rs2_data = ((rs2_addr == 5'd0) ? 32'd0 : regs[rs2_addr]);
  assign debug_x1 = regs[5'd1];
  assign debug_x2 = regs[5'd2];
  assign debug_x10 = regs[5'd10];
  assign debug_x11 = regs[5'd11];

  always @(posedge clk) begin
  if (rst) begin
  end
  else begin
    if ((rd_we & (rd_addr != 5'd0))) begin
      regs[rd_addr] <= rd_data;
    end
  end
  end

endmodule