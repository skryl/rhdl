module zero_extend(
  input [7:0] a,
  output [15:0] y
);

  assign y = {{8{1'b0}}, a};

endmodule