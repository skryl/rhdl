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