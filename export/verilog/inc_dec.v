module inc_dec(
  input [7:0] a,
  input inc,
  output [7:0] result,
  output cout
);

  wire [7:0] inc_result;
  wire [7:0] dec_result;
  wire inc_cout;
  wire dec_cout;

  assign inc_result = ((a + 8'd1) & 9'd255);
  assign dec_result = (a - 8'd1);
  assign inc_cout = (a == 8'd255);
  assign dec_cout = (a == 8'd0);
  assign result = (inc ? inc_result : dec_result);
  assign cout = (inc ? inc_cout : dec_cout);

endmodule