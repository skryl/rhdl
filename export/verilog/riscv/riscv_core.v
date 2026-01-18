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

module riscv_decoder(
  input [31:0] inst,
  output [6:0] opcode,
  output [4:0] rd,
  output [2:0] funct3,
  output [4:0] rs1,
  output [4:0] rs2,
  output [6:0] funct7,
  output reg_write,
  output mem_read,
  output mem_write,
  output mem_to_reg,
  output alu_src,
  output branch,
  output jump,
  output jalr,
  output [3:0] alu_op,
  output [2:0] inst_type
);

  assign opcode = inst[6:0];
  assign rd = inst[11:7];
  assign funct3 = inst[14:12];
  assign rs1 = inst[19:15];
  assign rs2 = inst[24:20];
  assign funct7 = inst[31:25];
  assign reg_write = ((inst[6:0] == 7'd55) ? 1'b1 : ((inst[6:0] == 7'd23) ? 1'b1 : ((inst[6:0] == 7'd111) ? 1'b1 : ((inst[6:0] == 7'd103) ? 1'b1 : ((inst[6:0] == 7'd3) ? 1'b1 : ((inst[6:0] == 7'd19) ? 1'b1 : ((inst[6:0] == 7'd51) ? 1'b1 : 1'b0)))))));
  assign mem_read = ((inst[6:0] == 7'd3) ? 1'b1 : 1'b0);
  assign mem_write = ((inst[6:0] == 7'd35) ? 1'b1 : 1'b0);
  assign mem_to_reg = ((inst[6:0] == 7'd3) ? 1'b1 : 1'b0);
  assign alu_src = ((inst[6:0] == 7'd51) ? 1'b0 : ((inst[6:0] == 7'd99) ? 1'b0 : 1'b1));
  assign branch = ((inst[6:0] == 7'd99) ? 1'b1 : 1'b0);
  assign jump = ((inst[6:0] == 7'd111) ? 1'b1 : ((inst[6:0] == 7'd103) ? 1'b1 : 1'b0));
  assign jalr = ((inst[6:0] == 7'd103) ? 1'b1 : 1'b0);
  assign alu_op = ((inst[6:0] == 7'd51) ? ((inst[14:12] == 3'd0) ? (((inst[31:25] >> 5) & 1'b1) ? 4'd1 : 4'd0) : ((inst[14:12] == 3'd1) ? 4'd2 : ((inst[14:12] == 3'd2) ? 4'd3 : ((inst[14:12] == 3'd3) ? 4'd4 : ((inst[14:12] == 3'd4) ? 4'd5 : ((inst[14:12] == 3'd5) ? (((inst[31:25] >> 5) & 1'b1) ? 4'd7 : 4'd6) : ((inst[14:12] == 3'd6) ? 4'd8 : ((inst[14:12] == 3'd7) ? 4'd9 : 4'd0)))))))) : ((inst[6:0] == 7'd19) ? ((inst[14:12] == 3'd0) ? 4'd0 : ((inst[14:12] == 3'd1) ? 4'd2 : ((inst[14:12] == 3'd2) ? 4'd3 : ((inst[14:12] == 3'd3) ? 4'd4 : ((inst[14:12] == 3'd4) ? 4'd5 : ((inst[14:12] == 3'd5) ? (((inst[31:25] >> 5) & 1'b1) ? 4'd7 : 4'd6) : ((inst[14:12] == 3'd6) ? 4'd8 : ((inst[14:12] == 3'd7) ? 4'd9 : 4'd0)))))))) : ((inst[6:0] == 7'd55) ? 4'd11 : ((inst[6:0] == 7'd23) ? 4'd0 : ((inst[6:0] == 7'd111) ? 4'd0 : ((inst[6:0] == 7'd103) ? 4'd0 : ((inst[6:0] == 7'd99) ? 4'd1 : ((inst[6:0] == 7'd3) ? 4'd0 : ((inst[6:0] == 7'd35) ? 4'd0 : 4'd0)))))))));
  assign inst_type = ((inst[6:0] == 7'd51) ? 3'd0 : ((inst[6:0] == 7'd19) ? 3'd1 : ((inst[6:0] == 7'd3) ? 3'd1 : ((inst[6:0] == 7'd103) ? 3'd1 : ((inst[6:0] == 7'd35) ? 3'd2 : ((inst[6:0] == 7'd99) ? 3'd3 : ((inst[6:0] == 7'd55) ? 3'd4 : ((inst[6:0] == 7'd23) ? 3'd4 : ((inst[6:0] == 7'd111) ? 3'd5 : 3'd0)))))))));

endmodule

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

module riscv_program_counter(
  input clk,
  input rst,
  input [31:0] pc_next,
  input pc_we,
  output reg [31:0] pc
);

  always @(posedge clk) begin
  if (rst) begin
    pc <= 32'd0;
  end
  else begin
    pc <= (pc_we ? pc_next : pc);
  end
  end

endmodule

module riscv_register_file(
  input clk,
  input rst,
  input [4:0] rs1_addr,
  input [4:0] rs2_addr,
  output [31:0] rs1_data,
  output [31:0] rs2_data,
  input [4:0] rd_addr,
  input [31:0] rd_data,
  input rd_we,
  output [31:0] debug_x1,
  output [31:0] debug_x2,
  output [31:0] debug_x10,
  output [31:0] debug_x11
);

  reg [31:0] regs [0:31];

  assign rs1_data = ((rs1_addr == 5'd0) ? 32'd0 : regs[rs1_addr]);
  assign rs2_data = ((rs2_addr == 5'd0) ? 32'd0 : regs[rs2_addr]);
  assign debug_x1 = regs[5'd1];
  assign debug_x2 = regs[5'd2];
  assign debug_x10 = regs[5'd10];
  assign debug_x11 = regs[5'd11];

  always @(posedge clk) begin
  if (rst) begin
  end
  else begin
    if ((rd_we & (rd_addr != 5'd0))) begin
      regs[rd_addr] <= rd_data;
    end
  end
  end

endmodule