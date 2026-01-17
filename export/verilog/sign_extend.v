module sign_extend(
  input [7:0] a,
  output [15:0] y
);

  wire sign;
  wire [7:0] extension;

  assign sign = a[7];
  assign extension = (sign ? 8'd255 : 8'd0);
  assign y = {extension, a};

endmodule