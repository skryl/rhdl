# MOS 6502 Address Generator - Synthesizable DSL Version
# Computes effective addresses for all 6502 addressing modes
# Combinational logic - direct Verilog synthesis

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'

module MOS6502S
  class AddressGenerator < RHDL::HDL::SimComponent
    include RHDL::DSL::Behavior

    # Addressing mode constants
    MODE_IMPLIED     = 0x00
    MODE_ACCUMULATOR = 0x01
    MODE_IMMEDIATE   = 0x02
    MODE_ZERO_PAGE   = 0x03
    MODE_ZERO_PAGE_X = 0x04
    MODE_ZERO_PAGE_Y = 0x05
    MODE_ABSOLUTE    = 0x06
    MODE_ABSOLUTE_X  = 0x07
    MODE_ABSOLUTE_Y  = 0x08
    MODE_INDIRECT    = 0x09
    MODE_INDEXED_IND = 0x0A
    MODE_INDIRECT_IDX = 0x0B
    MODE_RELATIVE    = 0x0C
    MODE_STACK       = 0x0D

    STACK_BASE = 0x0100

    port_input :mode, width: 4
    port_input :operand_lo, width: 8
    port_input :operand_hi, width: 8
    port_input :x_reg, width: 8
    port_input :y_reg, width: 8
    port_input :pc, width: 16
    port_input :sp, width: 8
    port_input :indirect_lo, width: 8
    port_input :indirect_hi, width: 8

    port_output :eff_addr, width: 16
    port_output :page_cross
    port_output :is_zero_page

    def propagate
      mode = in_val(:mode) & 0x0F
      operand_lo = in_val(:operand_lo) & 0xFF
      operand_hi = in_val(:operand_hi) & 0xFF
      x = in_val(:x_reg) & 0xFF
      y = in_val(:y_reg) & 0xFF
      pc = in_val(:pc) & 0xFFFF
      sp = in_val(:sp) & 0xFF
      ind_lo = in_val(:indirect_lo) & 0xFF
      ind_hi = in_val(:indirect_hi) & 0xFF

      eff_addr = 0
      page_cross = 0
      is_zp = 0

      case mode
      when MODE_IMPLIED, MODE_ACCUMULATOR, MODE_IMMEDIATE
        eff_addr = 0

      when MODE_ZERO_PAGE
        eff_addr = operand_lo
        is_zp = 1

      when MODE_ZERO_PAGE_X
        eff_addr = (operand_lo + x) & 0xFF
        is_zp = 1

      when MODE_ZERO_PAGE_Y
        eff_addr = (operand_lo + y) & 0xFF
        is_zp = 1

      when MODE_ABSOLUTE
        eff_addr = (operand_hi << 8) | operand_lo

      when MODE_ABSOLUTE_X
        base = (operand_hi << 8) | operand_lo
        eff_addr = (base + x) & 0xFFFF
        page_cross = ((eff_addr >> 8) != operand_hi) ? 1 : 0

      when MODE_ABSOLUTE_Y
        base = (operand_hi << 8) | operand_lo
        eff_addr = (base + y) & 0xFFFF
        page_cross = ((eff_addr >> 8) != operand_hi) ? 1 : 0

      when MODE_INDIRECT
        eff_addr = (ind_hi << 8) | ind_lo

      when MODE_INDEXED_IND
        eff_addr = (ind_hi << 8) | ind_lo

      when MODE_INDIRECT_IDX
        base = (ind_hi << 8) | ind_lo
        eff_addr = (base + y) & 0xFFFF
        page_cross = ((eff_addr >> 8) != ind_hi) ? 1 : 0

      when MODE_RELATIVE
        # Sign extend 8-bit offset
        offset = operand_lo
        signed_offset = (offset & 0x80) != 0 ? (offset - 256) : offset
        target = (pc + signed_offset) & 0xFFFF
        eff_addr = target
        page_cross = ((target >> 8) != (pc >> 8)) ? 1 : 0

      when MODE_STACK
        eff_addr = STACK_BASE | sp
      end

      out_set(:eff_addr, eff_addr)
      out_set(:page_cross, page_cross)
      out_set(:is_zero_page, is_zp)
    end

    def self.to_verilog
      <<~VERILOG
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
      VERILOG
    end
  end
end
