// MOS 6502 Address Latch - Synthesizable Verilog
// Generated from RHDL Behavior DSL
module mos6502s_address_latch (
  input         clk,
  input         rst,
  input         load_lo,
  input         load_hi,
  input         load_full,
  input   [7:0] data_in,
  input  [15:0] addr_in,
  output [15:0] addr,
  output  [7:0] addr_lo,
  output  [7:0] addr_hi
);

  reg [7:0] addr_lo_reg;
  reg [7:0] addr_hi_reg;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      addr_lo_reg <= 8'h00;
      addr_hi_reg <= 8'h00;
    end else if (load_full) begin
      addr_lo_reg <= addr_in[7:0];
      addr_hi_reg <= addr_in[15:8];
    end else begin
      if (load_lo) addr_lo_reg <= data_in;
      if (load_hi) addr_hi_reg <= data_in;
    end
  end

  assign addr = {addr_hi_reg, addr_lo_reg};
  assign addr_lo = addr_lo_reg;
  assign addr_hi = addr_hi_reg;

endmodule
