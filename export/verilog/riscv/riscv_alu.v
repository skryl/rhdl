module riscv_alu(
  input [31:0] a,
  input [31:0] b,
  input [3:0] op,
  output [31:0] result,
  output zero
);

  wire [31:0] add_result;
  wire [31:0] sub_result;
  wire [31:0] xor_result;
  wire [31:0] or_result;
  wire [31:0] and_result;
  wire [4:0] shamt;
  wire [31:0] sll_result;
  wire [31:0] srl_result;
  wire [31:0] sra_result;
  wire [31:0] slt_result;
  wire [31:0] sltu_result;

  assign add_result = ((a + b) & 33'd4294967295);
  assign sub_result = (a - b);
  assign xor_result = (a ^ b);
  assign or_result = (a | b);
  assign and_result = (a & b);
  assign shamt = b[4:0];
  assign sll_result = (a << {{27{1'b0}}, shamt});
  assign srl_result = (a >> {{27{1'b0}}, shamt});
  assign sra_result = (a[31] ? ((a >> {{27{1'b0}}, shamt}) | ~(32'd4294967295 >> {{27{1'b0}}, shamt})) : (a >> {{27{1'b0}}, shamt}));
  assign slt_result = {31'd0, ((a[31] != b[31]) ? a[31] : sub_result[31])};
  assign sltu_result = {31'd0, (a < b)};
  assign result = ((op == 4'd0) ? add_result : ((op == 4'd1) ? sub_result : ((op == 4'd2) ? sll_result : ((op == 4'd3) ? slt_result : ((op == 4'd4) ? sltu_result : ((op == 4'd5) ? xor_result : ((op == 4'd6) ? srl_result : ((op == 4'd7) ? sra_result : ((op == 4'd8) ? or_result : ((op == 4'd9) ? and_result : ((op == 4'd10) ? a : ((op == 4'd11) ? b : add_result))))))))))));
  assign zero = (((op == 4'd0) ? add_result : ((op == 4'd1) ? sub_result : ((op == 4'd2) ? sll_result : ((op == 4'd3) ? slt_result : ((op == 4'd4) ? sltu_result : ((op == 4'd5) ? xor_result : ((op == 4'd6) ? srl_result : ((op == 4'd7) ? sra_result : ((op == 4'd8) ? or_result : ((op == 4'd9) ? and_result : ((op == 4'd10) ? a : ((op == 4'd11) ? b : add_result)))))))))))) & 32'd1);

endmodule