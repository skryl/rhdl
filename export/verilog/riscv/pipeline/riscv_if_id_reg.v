module riscv_if_id_reg(
  input clk,
  input rst,
  input stall,
  input flush,
  input [31:0] pc_in,
  input [31:0] inst_in,
  input [31:0] pc_plus4_in,
  output reg [31:0] pc_out,
  output reg [31:0] inst_out,
  output reg [31:0] pc_plus4_out
);

  always @(posedge clk) begin
  if (rst) begin
    pc_out <= 32'd0;
    inst_out <= 32'd19;
    pc_plus4_out <= 32'd4;
  end
  else begin
    pc_out <= (flush ? 32'd0 : (stall ? pc_out : pc_in));
    inst_out <= (flush ? 32'd19 : (stall ? inst_out : inst_in));
    pc_plus4_out <= (flush ? 32'd4 : (stall ? pc_plus4_out : pc_plus4_in));
  end
  end

endmodule