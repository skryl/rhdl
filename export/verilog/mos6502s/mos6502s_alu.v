module mos6502s_alu(
  input [7:0] a,
  input [7:0] b,
  input c_in,
  input d_flag,
  input [3:0] op,
  output [7:0] result,
  output n,
  output z,
  output c,
  output v
);

  wire [8:0] bin_sum;
  wire [7:0] b_inv;
  wire [8:0] bin_diff;
  wire [3:0] al;
  wire [3:0] ah;
  wire [3:0] bl;
  wire [3:0] bh;
  wire [4:0] sum_l_raw;
  wire carry_l;
  wire [3:0] adj_l;
  wire [4:0] sum_h_raw;
  wire carry_h;
  wire [3:0] adj_h;
  wire [4:0] diff_l_raw;
  wire borrow_l;
  wire [3:0] sub_adj_l;
  wire [4:0] diff_h_raw;
  wire borrow_h;
  wire [3:0] sub_adj_h;
  wire [7:0] bcd_add_result;
  wire [7:0] bcd_sub_result;
  wire [7:0] and_result;
  wire [7:0] ora_result;
  wire [7:0] eor_result;
  wire [7:0] asl_result;
  wire [7:0] lsr_result;
  wire [7:0] rol_result;
  wire [7:0] ror_result;
  wire [7:0] inc_result;
  wire [7:0] dec_result;
  wire [7:0] cmp_result;
  wire [7:0] adc_result;
  wire [7:0] sbc_result;

  assign bin_sum = ((({1'b0, a} + {1'b0, b}) + {{1{1'b0}}, {8'd0, c_in}}) & 11'd511);
  assign b_inv = ~b;
  assign bin_diff = ((({1'b0, a} + {1'b0, b_inv}) + {{1{1'b0}}, {8'd0, c_in}}) & 11'd511);
  assign al = a[3:0];
  assign ah = a[7:4];
  assign bl = b[3:0];
  assign bh = b[7:4];
  assign sum_l_raw = ((({1'b0, al} + {1'b0, bl}) + {{1{1'b0}}, {4'd0, c_in}}) & 7'd31);
  assign carry_l = (sum_l_raw > 5'd9);
  assign adj_l = (carry_l ? (sum_l_raw + 5'd6)[3:0] : sum_l_raw[3:0]);
  assign sum_h_raw = ((({1'b0, ah} + {1'b0, bh}) + {{1{1'b0}}, {4'd0, carry_l}}) & 7'd31);
  assign carry_h = (sum_h_raw > 5'd9);
  assign adj_h = (carry_h ? (sum_h_raw + 5'd6)[3:0] : sum_h_raw[3:0]);
  assign diff_l_raw = (({1'b0, al} - {1'b0, bl}) - {4'd0, ~c_in});
  assign borrow_l = diff_l_raw[4];
  assign sub_adj_l = (borrow_l ? (diff_l_raw + 5'd10)[3:0] : diff_l_raw[3:0]);
  assign diff_h_raw = (({1'b0, ah} - {1'b0, bh}) - {4'd0, borrow_l});
  assign borrow_h = diff_h_raw[4];
  assign sub_adj_h = (borrow_h ? (diff_h_raw + 5'd10)[3:0] : diff_h_raw[3:0]);
  assign bcd_add_result = {adj_h, adj_l};
  assign bcd_sub_result = {sub_adj_h, sub_adj_l};
  assign and_result = (a & b);
  assign ora_result = (a | b);
  assign eor_result = (a ^ b);
  assign asl_result = {a[6:0], 1'b0};
  assign lsr_result = {1'b0, a[7:1]};
  assign rol_result = {a[6:0], c_in};
  assign ror_result = {c_in, a[7:1]};
  assign inc_result = (a + 8'd1)[7:0];
  assign dec_result = (a - 8'd1)[7:0];
  assign cmp_result = (a - b)[7:0];
  assign adc_result = (d_flag ? bcd_add_result : bin_sum[7:0]);
  assign sbc_result = (d_flag ? bcd_sub_result : bin_diff[7:0]);
  assign result = ((op == 4'd0) ? adc_result : ((op == 4'd1) ? sbc_result : ((op == 4'd2) ? and_result : ((op == 4'd3) ? ora_result : ((op == 4'd4) ? eor_result : ((op == 4'd5) ? asl_result : ((op == 4'd6) ? lsr_result : ((op == 4'd7) ? rol_result : ((op == 4'd8) ? ror_result : ((op == 4'd9) ? inc_result : ((op == 4'd10) ? dec_result : ((op == 4'd11) ? cmp_result : ((op == 4'd12) ? a : ((op == 4'd13) ? a : ((op == 4'd15) ? a : a)))))))))))))));
  assign n = ((op == 4'd0) ? adc_result[7] : ((op == 4'd1) ? sbc_result[7] : ((op == 4'd2) ? and_result[7] : ((op == 4'd3) ? ora_result[7] : ((op == 4'd4) ? eor_result[7] : ((op == 4'd5) ? asl_result[7] : ((op == 4'd6) ? 1'b0 : ((op == 4'd7) ? rol_result[7] : ((op == 4'd8) ? ror_result[7] : ((op == 4'd9) ? inc_result[7] : ((op == 4'd10) ? dec_result[7] : ((op == 4'd11) ? cmp_result[7] : ((op == 4'd12) ? b[7] : ((op == 4'd13) ? a[7] : 1'b0))))))))))))));
  assign z = ((op == 4'd0) ? (adc_result == 8'd0) : ((op == 4'd1) ? (sbc_result == 8'd0) : ((op == 4'd2) ? (and_result == 8'd0) : ((op == 4'd3) ? (ora_result == 8'd0) : ((op == 4'd4) ? (eor_result == 8'd0) : ((op == 4'd5) ? (asl_result == 8'd0) : ((op == 4'd6) ? (lsr_result == 8'd0) : ((op == 4'd7) ? (rol_result == 8'd0) : ((op == 4'd8) ? (ror_result == 8'd0) : ((op == 4'd9) ? (inc_result == 8'd0) : ((op == 4'd10) ? (dec_result == 8'd0) : ((op == 4'd11) ? (a == b) : ((op == 4'd12) ? ((a & b) == 8'd0) : ((op == 4'd13) ? (a == 8'd0) : 1'b0))))))))))))));
  assign c = ((op == 4'd0) ? (d_flag ? carry_h : bin_sum[8]) : ((op == 4'd1) ? (d_flag ? ~borrow_h : bin_diff[8]) : ((op == 4'd5) ? a[7] : ((op == 4'd6) ? a[0] : ((op == 4'd7) ? a[7] : ((op == 4'd8) ? a[0] : ((op == 4'd11) ? (a >= b) : ((op == 4'd15) ? c_in : 1'b0))))))));
  assign v = ((op == 4'd0) ? ((a[7] == b[7]) & (adc_result[7] != a[7])) : ((op == 4'd1) ? ((a[7] != b[7]) & (sbc_result[7] != a[7])) : ((op == 4'd12) ? b[6] : 1'b0)));

endmodule