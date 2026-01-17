// MOS 6502 Stack Pointer - Synthesizable Verilog
// Generated from RHDL Behavior DSL
module mos6502s_stack_pointer (
  input        clk,
  input        rst,
  input        inc,
  input        dec,
  input        load,
  input  [7:0] data_in,
  output reg [7:0] sp,
  output [15:0] addr,
  output [15:0] addr_plus1
);

  localparam STACK_BASE = 16'h0100;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      sp <= 8'hFD;
    end else if (load) begin
      sp <= data_in;
    end else if (dec) begin
      sp <= sp - 8'h01;
    end else if (inc) begin
      sp <= sp + 8'h01;
    end
  end

  assign addr = STACK_BASE | {8'h00, sp};
  assign addr_plus1 = STACK_BASE | {8'h00, sp + 8'h01};

endmodule
