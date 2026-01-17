// MOS 6502 Registers (A, X, Y) - Synthesizable Verilog
// Generated from RHDL Behavior DSL
module mos6502s_registers (
  input        clk,
  input        rst,
  input  [7:0] data_in,
  input        load_a,
  input        load_x,
  input        load_y,
  output reg [7:0] a,
  output reg [7:0] x,
  output reg [7:0] y
);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      a <= 8'h00;
      x <= 8'h00;
      y <= 8'h00;
    end else begin
      if (load_a) a <= data_in;
      if (load_x) x <= data_in;
      if (load_y) y <= data_in;
    end
  end

endmodule
