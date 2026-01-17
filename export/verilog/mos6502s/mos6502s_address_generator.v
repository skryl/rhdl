// MOS 6502 Address Generator - Synthesizable Verilog
// Generated from RHDL Behavior DSL
module mos6502s_address_generator (
  input  [3:0]  mode,
  input  [7:0]  operand_lo,
  input  [7:0]  operand_hi,
  input  [7:0]  x_reg,
  input  [7:0]  y_reg,
  input  [15:0] pc,
  input  [7:0]  sp,
  input  [7:0]  indirect_lo,
  input  [7:0]  indirect_hi,
  output reg [15:0] eff_addr,
  output reg        page_cross,
  output reg        is_zero_page
);

  // Addressing mode constants
  localparam MODE_IMPLIED     = 4'h0;
  localparam MODE_ACCUMULATOR = 4'h1;
  localparam MODE_IMMEDIATE   = 4'h2;
  localparam MODE_ZERO_PAGE   = 4'h3;
  localparam MODE_ZERO_PAGE_X = 4'h4;
  localparam MODE_ZERO_PAGE_Y = 4'h5;
  localparam MODE_ABSOLUTE    = 4'h6;
  localparam MODE_ABSOLUTE_X  = 4'h7;
  localparam MODE_ABSOLUTE_Y  = 4'h8;
  localparam MODE_INDIRECT    = 4'h9;
  localparam MODE_INDEXED_IND = 4'hA;
  localparam MODE_INDIRECT_IDX = 4'hB;
  localparam MODE_RELATIVE    = 4'hC;
  localparam MODE_STACK       = 4'hD;

  localparam STACK_BASE = 16'h0100;

  // Internal wires for address calculations
  wire [15:0] abs_addr;
  wire [15:0] abs_x_addr;
  wire [15:0] abs_y_addr;
  wire [15:0] ind_addr;
  wire [15:0] ind_y_addr;
  wire [15:0] rel_addr;
  wire [8:0]  signed_offset;

  assign abs_addr = {operand_hi, operand_lo};
  assign abs_x_addr = abs_addr + {8'h00, x_reg};
  assign abs_y_addr = abs_addr + {8'h00, y_reg};
  assign ind_addr = {indirect_hi, indirect_lo};
  assign ind_y_addr = ind_addr + {8'h00, y_reg};

  // Sign extension for relative addressing
  assign signed_offset = operand_lo[7] ? {1'b1, operand_lo} : {1'b0, operand_lo};
  assign rel_addr = pc + {{7{operand_lo[7]}}, operand_lo};

  always @* begin
    eff_addr = 16'h0000;
    page_cross = 1'b0;
    is_zero_page = 1'b0;

    case (mode)
      MODE_IMPLIED, MODE_ACCUMULATOR, MODE_IMMEDIATE: begin
        eff_addr = 16'h0000;
      end

      MODE_ZERO_PAGE: begin
        eff_addr = {8'h00, operand_lo};
        is_zero_page = 1'b1;
      end

      MODE_ZERO_PAGE_X: begin
        eff_addr = {8'h00, operand_lo + x_reg};
        is_zero_page = 1'b1;
      end

      MODE_ZERO_PAGE_Y: begin
        eff_addr = {8'h00, operand_lo + y_reg};
        is_zero_page = 1'b1;
      end

      MODE_ABSOLUTE: begin
        eff_addr = abs_addr;
      end

      MODE_ABSOLUTE_X: begin
        eff_addr = abs_x_addr;
        page_cross = (abs_x_addr[15:8] != operand_hi);
      end

      MODE_ABSOLUTE_Y: begin
        eff_addr = abs_y_addr;
        page_cross = (abs_y_addr[15:8] != operand_hi);
      end

      MODE_INDIRECT: begin
        eff_addr = ind_addr;
      end

      MODE_INDEXED_IND: begin
        eff_addr = ind_addr;
      end

      MODE_INDIRECT_IDX: begin
        eff_addr = ind_y_addr;
        page_cross = (ind_y_addr[15:8] != indirect_hi);
      end

      MODE_RELATIVE: begin
        eff_addr = rel_addr;
        page_cross = (rel_addr[15:8] != pc[15:8]);
      end

      MODE_STACK: begin
        eff_addr = STACK_BASE | {8'h00, sp};
      end

      default: begin
        eff_addr = 16'h0000;
      end
    endcase
  end

endmodule
