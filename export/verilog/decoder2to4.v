module decoder2to4(
  input [1:0] a,
  input en,
  output y0,
  output y1,
  output y2,
  output y3
);

  assign y0 = (en & (a == 2'd0));
  assign y1 = (en & (a == 2'd1));
  assign y2 = (en & (a == 2'd2));
  assign y3 = (en & (a == 2'd3));

endmodule