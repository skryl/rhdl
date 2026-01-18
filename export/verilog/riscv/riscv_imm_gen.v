module riscv_imm_gen(
  input [31:0] inst,
  output [31:0] imm
);

  wire [31:0] i_imm;
  wire [31:0] s_imm;
  wire [31:0] b_imm;
  wire [31:0] u_imm;
  wire [31:0] j_imm;

  assign i_imm = {{inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31]}, inst[31:20]};
  assign s_imm = {{inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31]}, {inst[31:25], inst[11:7]}};
  assign b_imm = {{inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31]}, {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}};
  assign u_imm = {inst[31:12], 12'd0};
  assign j_imm = {{inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31], inst[31]}, {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}};
  assign imm = ((inst[6:0] == 7'd103) ? i_imm : ((inst[6:0] == 7'd3) ? i_imm : ((inst[6:0] == 7'd19) ? i_imm : ((inst[6:0] == 7'd35) ? s_imm : ((inst[6:0] == 7'd99) ? b_imm : ((inst[6:0] == 7'd55) ? u_imm : ((inst[6:0] == 7'd23) ? u_imm : ((inst[6:0] == 7'd111) ? j_imm : ((inst[6:0] == 7'd115) ? i_imm : ((inst[6:0] == 7'd15) ? i_imm : 32'd0))))))))));

endmodule