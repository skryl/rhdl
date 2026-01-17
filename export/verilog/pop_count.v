module pop_count(
  input [7:0] a,
  output [3:0] count
);

  assign count = ((((((((a[0] + a[1]) + {{1{1'b0}}, a[2]}) + {{2{1'b0}}, a[3]}) + {{3{1'b0}}, a[4]}) + {{4{1'b0}}, a[5]}) + {{5{1'b0}}, a[6]}) + {{6{1'b0}}, a[7]}) & 8'd15);

endmodule