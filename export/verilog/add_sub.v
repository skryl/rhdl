module add_sub(
  input [7:0] a,
  input [7:0] b,
  input sub,
  output [7:0] result,
  output cout,
  output overflow,
  output zero,
  output negative
);

  wire [7:0] sum_result;
  wire [7:0] diff_result;
  wire add_carry;
  wire sub_borrow;
  wire a_sign;
  wire b_sign;
  wire [7:0] result_val;
  wire r_sign;
  wire add_overflow;
  wire sub_overflow;

  assign sum_result = ((a + b) & 9'd255);
  assign diff_result = (a - b);
  assign add_carry = (a + b)[8];
  assign sub_borrow = (a < b);
  assign a_sign = a[7];
  assign b_sign = b[7];
  assign result_val = (sub ? diff_result : sum_result);
  assign r_sign = result_val[7];
  assign add_overflow = ((a_sign == b_sign) & (r_sign ^ a_sign));
  assign sub_overflow = ((a_sign ^ b_sign) & (r_sign ^ a_sign));
  assign result = (sub ? diff_result : sum_result);
  assign cout = (sub ? sub_borrow : add_carry);
  assign overflow = (sub ? sub_overflow : add_overflow);
  assign zero = (result_val == 8'd0);
  assign negative = r_sign;

endmodule