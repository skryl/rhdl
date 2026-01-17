// MOS 6502 Indirect Address Calculator - Synthesizable Verilog
// Generated from RHDL Behavior DSL
module mos6502s_indirect_addr_calc (
  input  [3:0]  mode,
  input  [7:0]  operand_lo,
  input  [7:0]  operand_hi,
  input  [7:0]  x_reg,
  output reg [15:0] ptr_addr_lo,
  output reg [15:0] ptr_addr_hi
);

  localparam MODE_INDIRECT    = 4'h9;
  localparam MODE_INDEXED_IND = 4'hA;
  localparam MODE_INDIRECT_IDX = 4'hB;

  wire [15:0] abs_addr;
  wire [7:0] zp_addr_x;

  assign abs_addr = {operand_hi, operand_lo};
  assign zp_addr_x = operand_lo + x_reg;

  always @* begin
    ptr_addr_lo = 16'h0000;
    ptr_addr_hi = 16'h0000;

    case (mode)
      MODE_INDIRECT: begin
        ptr_addr_lo = abs_addr;
        // 6502 bug: page wrap on $xxFF
        ptr_addr_hi = (operand_lo == 8'hFF) ? {operand_hi, 8'h00} : (abs_addr + 16'h0001);
      end

      MODE_INDEXED_IND: begin
        ptr_addr_lo = {8'h00, zp_addr_x};
        ptr_addr_hi = {8'h00, zp_addr_x + 8'h01};  // Wraps in ZP
      end

      MODE_INDIRECT_IDX: begin
        ptr_addr_lo = {8'h00, operand_lo};
        ptr_addr_hi = {8'h00, operand_lo + 8'h01};  // Wraps in ZP
      end

      default: begin
        ptr_addr_lo = 16'h0000;
        ptr_addr_hi = 16'h0000;
      end
    endcase
  end

endmodule
