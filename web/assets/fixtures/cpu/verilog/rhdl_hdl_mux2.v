module mux2 #(
  parameter width = 1
) (
  input a,
  input b,
  input sel,
  output y
);

  assign y = (sel ? b : a);

endmodule