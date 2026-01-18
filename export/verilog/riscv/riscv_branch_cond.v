module riscv_branch_cond(
  input [31:0] rs1_data,
  input [31:0] rs2_data,
  input [2:0] funct3,
  output branch_taken
);

  wire signed_lt;

  assign signed_lt = ((rs1_data[31] != rs2_data[31]) ? rs1_data[31] : (rs1_data < rs2_data));
  assign branch_taken = ((funct3 == 3'd0) ? (rs1_data == rs2_data) : ((funct3 == 3'd1) ? ~(rs1_data == rs2_data) : ((funct3 == 3'd4) ? signed_lt : ((funct3 == 3'd5) ? ~signed_lt : ((funct3 == 3'd6) ? (rs1_data < rs2_data) : ((funct3 == 3'd7) ? ~(rs1_data < rs2_data) : 1'b0))))));

endmodule