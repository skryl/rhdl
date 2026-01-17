module ripple_carry_adder(
  input [7:0] a,
  input [7:0] b,
  input cin,
  output [7:0] sum,
  output cout,
  output overflow
);

  wire [8:0] result;
  wire a_sign;
  wire b_sign;
  wire sum_sign;

  assign result = (((a + b) + {{8{1'b0}}, cin}) & 10'd511);
  assign a_sign = a[7];
  assign b_sign = b[7];
  assign sum_sign = result[7];
  assign sum = result[7:0];
  assign cout = result[8];
  assign overflow = ((a_sign ^ sum_sign) & ~(a_sign ^ b_sign));

endmodule