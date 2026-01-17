module mos6502s_memory(
  input clk,
  input [15:0] addr,
  input [7:0] data_in,
  input rw,
  input cs,
  output [7:0] data_out
);

  wire is_rom;
  wire [14:0] ram_addr;
  wire [14:0] rom_addr;
  reg [7:0] ram [0:32767];
  reg [7:0] rom [0:32767];

  assign is_rom = addr[15];
  assign ram_addr = addr[14:0];
  assign rom_addr = addr[14:0];
  assign data_out = (cs ? (is_rom ? rom[rom_addr] : ram[ram_addr]) : 8'd0);

  always @(posedge clk) begin
    if (((cs & ~rw) & ~addr[15])) begin
      ram[addr[14:0]] <= data_in;
    end
  end

endmodule