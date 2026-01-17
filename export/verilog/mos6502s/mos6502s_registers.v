module mos6502s_registers(
  input clk,
  input rst,
  input [7:0] data_in,
  input load_a,
  input load_x,
  input load_y,
  output reg [7:0] a,
  output reg [7:0] x,
  output reg [7:0] y
);

  always @(posedge clk) begin
  if (rst) begin
    a <= 8'd0;
    x <= 8'd0;
    y <= 8'd0;
  end
  else begin
    a <= (load_a ? data_in : a);
    x <= (load_x ? data_in : x);
    y <= (load_y ? data_in : y);
  end
  end

endmodule