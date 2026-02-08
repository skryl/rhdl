module apple2_disk_iirom(
  input clk,
  input [7:0] addr,
  output [7:0] dout
);

  reg [7:0] rom [0:255];

  assign dout = rom[addr];

endmodule