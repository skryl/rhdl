module demux2(
  input a,
  input sel,
  output y0,
  output y1
);

  assign y0 = (sel ? 1'b0 : a);
  assign y1 = (sel ? a : 1'b0);

endmodule