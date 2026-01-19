module zero_detect(
  input [7:0] a,
  output zero
);

  assign zero = (a == 8'd0);

endmodule