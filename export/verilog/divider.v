module divider(
  input [7:0] dividend,
  input [7:0] divisor,
  output [7:0] quotient,
  output [7:0] remainder,
  output div_by_zero
);

  wire is_zero;
  wire [7:0] normal_quotient;
  wire [7:0] normal_remainder;

  assign is_zero = (divisor == 8'd0);
  assign normal_quotient = (dividend / divisor);
  assign normal_remainder = (dividend % divisor);
  assign div_by_zero = is_zero;
  assign quotient = (is_zero ? 8'd0 : normal_quotient);
  assign remainder = (is_zero ? 8'd0 : normal_remainder);

endmodule