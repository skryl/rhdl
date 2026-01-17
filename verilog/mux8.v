module mux8(
  input in0,
  input in1,
  input in2,
  input in3,
  input in4,
  input in5,
  input in6,
  input in7,
  input [2:0] sel,
  output y
);

  assign y = ((sel == 3'd0) ? in0 : ((sel == 3'd1) ? in1 : ((sel == 3'd2) ? in2 : ((sel == 3'd3) ? in3 : ((sel == 3'd4) ? in4 : ((sel == 3'd5) ? in5 : ((sel == 3'd6) ? in6 : ((sel == 3'd7) ? in7 : 1'b0))))))));

endmodule