module mos6502s_address_latch(
  input clk,
  input rst,
  input load_lo,
  input load_hi,
  input load_full,
  input [7:0] data_in,
  input [15:0] addr_in,
  output reg [7:0] addr_lo,
  output reg [7:0] addr_hi,
  output [15:0] addr
);

  assign addr = {addr_hi, addr_lo};

  always @(posedge clk) begin
  if (rst) begin
    addr_lo <= 8'd0;
    addr_hi <= 8'd0;
  end
  else begin
    addr_lo <= (load_full ? addr_in[7:0] : (load_lo ? data_in : addr_lo));
    addr_hi <= (load_full ? addr_in[15:8] : (load_hi ? data_in : addr_hi));
  end
  end

endmodule