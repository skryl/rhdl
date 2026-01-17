module bitwise_not(
  input [7:0] a,
  output [7:0] y
);

  assign y = ~a;

endmodule