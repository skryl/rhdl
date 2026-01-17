module subtractor(
  input [7:0] a,
  input [7:0] b,
  input bin,
  output [7:0] diff,
  output bout,
  output overflow
);

  wire [7:0] diff_result;
  wire [8:0] b_plus_bin;
  wire a_sign;
  wire b_sign;
  wire diff_sign;

  assign diff_result = ((a - b) - {{7{1'b0}}, bin});
  assign b_plus_bin = (b + {{7{1'b0}}, bin});
  assign a_sign = a[7];
  assign b_sign = b[7];
  assign diff_sign = diff_result[7];
  assign diff = diff_result;
  assign bout = (a < (b_plus_bin & 9'd255));
  assign overflow = ((a_sign ^ b_sign) & (diff_sign ^ a_sign));

endmodule