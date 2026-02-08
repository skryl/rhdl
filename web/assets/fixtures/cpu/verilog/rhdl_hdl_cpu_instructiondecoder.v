module cpu_instruction_decoder(
  input [7:0] instruction,
  input zero_flag,
  output [3:0] alu_op,
  output alu_src,
  output reg_write,
  output mem_read,
  output mem_write,
  output branch,
  output jump,
  output [1:0] pc_src,
  output halt,
  output call,
  output ret,
  output [1:0] instr_length,
  output is_lda,
  output sta_indirect,
  output lda_indirect
);

  assign alu_op = ((instruction[7:4] == 4'd3) ? 1'b0 : ((instruction[7:4] == 4'd4) ? 1'b1 : ((instruction[7:4] == 4'd5) ? 2'd2 : ((instruction[7:4] == 4'd6) ? 2'd3 : ((instruction[7:4] == 4'd7) ? 3'd4 : ((instruction[7:4] == 4'd14) ? 4'd12 : ((instruction[7:4] == 4'd15) ? ((instruction == 8'd241) ? 4'd11 : ((instruction == 8'd242) ? 3'd5 : ((instruction == 8'd243) ? 1'b1 : 1'b0))) : 1'b0)))))));
  assign alu_src = ((instruction[7:4] == 4'd10) ? 1'b1 : 1'b0);
  assign reg_write = ((instruction[7:4] == 4'd1) ? 1'b1 : ((instruction[7:4] == 4'd3) ? 1'b1 : ((instruction[7:4] == 4'd4) ? 1'b1 : ((instruction[7:4] == 4'd5) ? 1'b1 : ((instruction[7:4] == 4'd6) ? 1'b1 : ((instruction[7:4] == 4'd7) ? 1'b1 : ((instruction[7:4] == 4'd10) ? 1'b1 : ((instruction[7:4] == 4'd14) ? 1'b1 : ((instruction[7:4] == 4'd15) ? (((instruction == 8'd241) | (instruction == 8'd242)) ? 1'b1 : 1'b0) : 1'b0)))))))));
  assign mem_read = ((instruction[7:4] == 4'd1) ? 1'b1 : ((instruction[7:4] == 4'd3) ? 1'b1 : ((instruction[7:4] == 4'd4) ? 1'b1 : ((instruction[7:4] == 4'd5) ? 1'b1 : ((instruction[7:4] == 4'd6) ? 1'b1 : ((instruction[7:4] == 4'd7) ? 1'b1 : ((instruction[7:4] == 4'd14) ? 1'b1 : ((instruction[7:4] == 4'd15) ? (((instruction == 8'd241) | (instruction == 8'd243)) ? 1'b1 : 1'b0) : 1'b0))))))));
  assign mem_write = ((instruction[7:4] == {{2{1'b0}}, 2'd2}) ? 1'b1 : 1'b0);
  assign branch = ((instruction[7:4] == 4'd8) ? 1'b1 : ((instruction[7:4] == 4'd9) ? 1'b1 : ((instruction[7:4] == 4'd15) ? (((instruction == 8'd248) | (instruction == 8'd250)) ? 1'b1 : 1'b0) : 1'b0)));
  assign jump = ((instruction[7:4] == 4'd11) ? 1'b1 : ((instruction[7:4] == 4'd15) ? ((instruction == 8'd249) ? 1'b1 : 1'b0) : 1'b0));
  assign pc_src = ((instruction[7:4] == 4'd8) ? (zero_flag ? 1'b1 : 1'b0) : ((instruction[7:4] == 4'd9) ? (zero_flag ? 1'b0 : 1'b1) : ((instruction[7:4] == 4'd11) ? 1'b1 : ((instruction[7:4] == 4'd12) ? 1'b1 : ((instruction[7:4] == 4'd15) ? ((instruction == 8'd248) ? (zero_flag ? 2'd2 : 1'b0) : ((instruction == 8'd249) ? 2'd2 : ((instruction == 8'd250) ? (zero_flag ? 1'b0 : 2'd2) : 1'b0))) : 1'b0)))));
  assign halt = ((instruction == 8'd240) ? 1'b1 : 1'b0);
  assign call = ((instruction[7:4] == 4'd12) ? 1'b1 : 1'b0);
  assign ret = ((instruction[7:4] == 4'd13) ? 1'b1 : 1'b0);
  assign is_lda = ((instruction[7:4] == 4'd1) ? 1'b1 : ((instruction[7:4] == 4'd10) ? 1'b1 : 1'b0));
  assign sta_indirect = ((instruction == {{2{1'b0}}, 6'd32}) ? 1'b1 : 1'b0);
  assign lda_indirect = ((instruction == {{3{1'b0}}, 5'd16}) ? 1'b1 : 1'b0);
  assign instr_length = ((instruction[7:4] == 4'd1) ? ((instruction == 8'd16) ? 2'd3 : ((instruction == 8'd17) ? 2'd2 : 1'b1)) : ((instruction[7:4] == 4'd2) ? ((instruction == 8'd32) ? 2'd3 : ((instruction == 8'd33) ? 2'd2 : 1'b1)) : ((instruction[7:4] == 4'd10) ? 2'd2 : ((instruction[7:4] == 4'd12) ? ((instruction == 8'd192) ? 2'd2 : 1'b1) : ((instruction[7:4] == 4'd15) ? ((instruction == 8'd241) ? 2'd2 : ((instruction == 8'd243) ? 2'd2 : ((instruction == 8'd248) ? 2'd3 : ((instruction == 8'd249) ? 2'd3 : ((instruction == 8'd250) ? 2'd3 : 1'b1))))) : 1'b1)))));

endmodule