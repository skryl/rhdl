module tristate_buffer(
  input a,
  input en,
  output y
);

  assign y = (en ? a : 1'b0);

endmodule