module mos6502s_data_latch(
  input clk,
  input rst,
  input load,
  input [7:0] data_in,
  output reg [7:0] data
);

  always @(posedge clk) begin
  if (rst) begin
    data <= 8'd0;
  end
  else begin
    data <= (load ? data_in : data);
  end
  end

endmodule