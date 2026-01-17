module multiplier(
  input [7:0] a,
  input [7:0] b,
  output [15:0] product
);

  assign product = (a * b);

endmodule