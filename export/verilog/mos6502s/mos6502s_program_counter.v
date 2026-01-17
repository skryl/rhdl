module mos6502s_program_counter(
  input clk,
  input rst,
  input inc,
  input load,
  input [15:0] addr_in,
  output reg [15:0] pc,
  output [7:0] pc_hi,
  output [7:0] pc_lo
);

  assign pc_hi = pc[15:8];
  assign pc_lo = pc[7:0];

  always @(posedge clk) begin
  if (rst) begin
    pc <= 16'd65532;
  end
  else begin
    pc <= (load ? (inc ? (addr_in + 16'd1) : addr_in) : (inc ? (pc + 16'd1) : pc));
  end
  end

endmodule