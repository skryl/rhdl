// MOS 6502 Instruction Register - Synthesizable Verilog
// Generated from RHDL Behavior DSL
module mos6502s_instruction_register (
  input        clk,
  input        rst,
  input        load_opcode,
  input        load_operand_lo,
  input        load_operand_hi,
  input  [7:0] data_in,
  output reg [7:0] opcode,
  output reg [7:0] operand_lo,
  output reg [7:0] operand_hi,
  output [15:0] operand
);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      opcode <= 8'h00;
      operand_lo <= 8'h00;
      operand_hi <= 8'h00;
    end else begin
      if (load_opcode) opcode <= data_in;
      if (load_operand_lo) operand_lo <= data_in;
      if (load_operand_hi) operand_hi <= data_in;
    end
  end

  assign operand = {operand_hi, operand_lo};

endmodule
