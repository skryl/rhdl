module alu(
  input [7:0] a,
  input [7:0] b,
  input [3:0] op,
  input cin,
  output [7:0] result,
  output cout,
  output zero,
  output negative,
  output overflow
);

  assign result = ((((a + b) + {{8{1'b0}}, (cin & 1'b1)}) & {{2{1'b0}}, 8'd255}) & 10'd255);
  assign cout = (((((a + b) + {{8{1'b0}}, (cin & 1'b1)}) >> {{6{1'b0}}, 4'd8}) & {{9{1'b0}}, 1'b1}) & 10'd1);
  assign zero = 1'b1;
  assign negative = ((((((a + b) + {{8{1'b0}}, (cin & 1'b1)}) & {{2{1'b0}}, 8'd255}) >> {{7{1'b0}}, 3'd7}) & {{9{1'b0}}, 1'b1}) & 10'd1);
  assign overflow = 1'b1;

endmodule