module encoder8to3(
  input [7:0] a,
  output [2:0] y,
  output valid
);

  wire is_7;
  wire is_6;
  wire is_5;
  wire is_4;
  wire is_3;
  wire is_2;
  wire is_1;
  wire is_0;
  wire y2;
  wire y1;
  wire y0;

  assign is_7 = a[7];
  assign is_6 = (~a[7] & a[6]);
  assign is_5 = ((~a[7] & ~a[6]) & a[5]);
  assign is_4 = (((~a[7] & ~a[6]) & ~a[5]) & a[4]);
  assign is_3 = ((((~a[7] & ~a[6]) & ~a[5]) & ~a[4]) & a[3]);
  assign is_2 = (((((~a[7] & ~a[6]) & ~a[5]) & ~a[4]) & ~a[3]) & a[2]);
  assign is_1 = ((((((~a[7] & ~a[6]) & ~a[5]) & ~a[4]) & ~a[3]) & ~a[2]) & a[1]);
  assign is_0 = (((((((~a[7] & ~a[6]) & ~a[5]) & ~a[4]) & ~a[3]) & ~a[2]) & ~a[1]) & a[0]);
  assign y2 = (((is_4 | is_5) | is_6) | is_7);
  assign y1 = (((is_2 | is_3) | is_6) | is_7);
  assign y0 = (((is_1 | is_3) | is_5) | is_7);
  assign y = {y2, y1, y0};
  assign valid = (((((((a[7] | a[6]) | a[5]) | a[4]) | a[3]) | a[2]) | a[1]) | a[0]);

endmodule