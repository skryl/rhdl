module riscv_program_counter(
  input clk,
  input rst,
  input [31:0] pc_next,
  input pc_we,
  output reg [31:0] pc
);

  always @(posedge clk) begin
  if (rst) begin
    pc <= 32'd0;
  end
  else begin
    pc <= (pc_we ? pc_next : pc);
  end
  end

endmodule