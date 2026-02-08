module apple2_character_rom(
  input clk,
  input [8:0] addr,
  output [4:0] dout
);

  reg [4:0] rom [0:511];

  assign dout = rom[addr];

endmodule