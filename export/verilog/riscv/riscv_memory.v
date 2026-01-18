module riscv_memory(
  input clk,
  input rst,
  input [31:0] addr,
  input [31:0] write_data,
  input mem_read,
  input mem_write,
  input [2:0] funct3,
  output [31:0] read_data
);

  reg [7:0] mem;
  wire [7:0] byte0;
  wire [7:0] byte1;
  wire [7:0] byte2;
  wire [7:0] byte3;
  wire [31:0] word_data;
  wire [15:0] half_data;

  assign byte0 = mem[addr];
  assign byte1 = mem[(addr + 32'd1)];
  assign byte2 = mem[(addr + 32'd2)];
  assign byte3 = mem[(addr + 32'd3)];

endmodule