module decoder3to8(
  input [2:0] a,
  input en,
  output y0,
  output y1,
  output y2,
  output y3,
  output y4,
  output y5,
  output y6,
  output y7
);

  assign y0 = (en & (a == 3'd0));
  assign y1 = (en & (a == 3'd1));
  assign y2 = (en & (a == 3'd2));
  assign y3 = (en & (a == 3'd3));
  assign y4 = (en & (a == 3'd4));
  assign y5 = (en & (a == 3'd5));
  assign y6 = (en & (a == 3'd6));
  assign y7 = (en & (a == 3'd7));

endmodule