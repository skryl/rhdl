// MOS 6502 Data Latch - Synthesizable Verilog
// Generated from RHDL Behavior DSL
module mos6502s_data_latch (
  input        clk,
  input        rst,
  input        load,
  input  [7:0] data_in,
  output reg [7:0] data
);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      data <= 8'h00;
    end else if (load) begin
      data <= data_in;
    end
  end

endmodule
