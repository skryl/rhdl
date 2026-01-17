# MOS 6502 Indirect Address Calculator - Synthesizable DSL Version
# Helper for computing indirect address fetch locations

require_relative '../../../lib/rhdl'
require_relative 'address_generator'

module MOS6502
  # Helper for computing indirect address fetch locations - DSL Version
  class IndirectAddressCalc < RHDL::HDL::SimComponent
    port_input :mode, width: 4
    port_input :operand_lo, width: 8
    port_input :operand_hi, width: 8
    port_input :x_reg, width: 8

    port_output :ptr_addr_lo, width: 16
    port_output :ptr_addr_hi, width: 16

    def propagate
      mode = in_val(:mode) & 0x0F
      operand_lo = in_val(:operand_lo) & 0xFF
      operand_hi = in_val(:operand_hi) & 0xFF
      x = in_val(:x_reg) & 0xFF

      ptr_lo = 0
      ptr_hi = 0

      case mode
      when AddressGenerator::MODE_INDIRECT
        base = (operand_hi << 8) | operand_lo
        ptr_lo = base
        # 6502 bug: if low byte is $FF, high byte comes from xx00
        ptr_hi = ((base & 0xFF) == 0xFF) ? (base & 0xFF00) : ((base + 1) & 0xFFFF)

      when AddressGenerator::MODE_INDEXED_IND
        zp_addr = (operand_lo + x) & 0xFF
        ptr_lo = zp_addr
        ptr_hi = (zp_addr + 1) & 0xFF

      when AddressGenerator::MODE_INDIRECT_IDX
        ptr_lo = operand_lo
        ptr_hi = (operand_lo + 1) & 0xFF
      end

      out_set(:ptr_addr_lo, ptr_lo)
      out_set(:ptr_addr_hi, ptr_hi)
    end

    def self.to_verilog
      <<~VERILOG
        // MOS 6502 Indirect Address Calculator - Synthesizable Verilog
        module mos6502_indirect_addr_calc (
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
      VERILOG
    end
  end
end
