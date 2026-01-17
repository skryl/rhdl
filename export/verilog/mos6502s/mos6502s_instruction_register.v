module mos6502s_instruction_register(
  input clk,
  input rst,
  input load_opcode,
  input load_operand_lo,
  input load_operand_hi,
  input [7:0] data_in,
  output reg [7:0] opcode,
  output reg [7:0] operand_lo,
  output reg [7:0] operand_hi,
  output [15:0] operand
);

  assign operand = {operand_hi, operand_lo};

  always @(posedge clk) begin
  if (rst) begin
    opcode <= 8'd0;
    operand_lo <= 8'd0;
    operand_hi <= 8'd0;
  end
  else begin
    opcode <= (load_opcode ? data_in : opcode);
    operand_lo <= (load_operand_lo ? data_in : operand_lo);
    operand_hi <= (load_operand_hi ? data_in : operand_hi);
  end
  end

endmodule