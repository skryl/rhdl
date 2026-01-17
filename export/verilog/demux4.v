module demux4(
  input a,
  input [1:0] sel,
  output y0,
  output y1,
  output y2,
  output y3
);

  wire sel_0;
  wire sel_1;
  wire sel_2;
  wire sel_3;

  assign sel_0 = (~sel[1] & ~sel[0]);
  assign sel_1 = (~sel[1] & sel[0]);
  assign sel_2 = (sel[1] & ~sel[0]);
  assign sel_3 = (sel[1] & sel[0]);
  assign y0 = (sel_0 ? a : 1'b0);
  assign y1 = (sel_1 ? a : 1'b0);
  assign y2 = (sel_2 ? a : 1'b0);
  assign y3 = (sel_3 ? a : 1'b0);

endmodule