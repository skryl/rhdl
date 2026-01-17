module encoder4to2(
  input [3:0] a,
  output [1:0] y,
  output valid
);

  wire is_3;
  wire is_2;
  wire is_1;
  wire is_0;

  assign is_3 = a[3];
  assign is_2 = (~a[3] & a[2]);
  assign is_1 = ((~a[3] & ~a[2]) & a[1]);
  assign is_0 = (((~a[3] & ~a[2]) & ~a[1]) & a[0]);
  assign y = {(is_3 | is_2), (is_3 | is_1)};
  assign valid = (((a[3] | a[2]) | a[1]) | a[0]);

endmodule