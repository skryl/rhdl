# MOS 6502 Address Generator - Synthesizable DSL Version
# Computes effective addresses for all 6502 addressing modes
# Combinational logic - synthesized from behavior DSL

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'

module MOS6502
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

    input :mode, width: 4
    input :operand_lo, width: 8
    input :operand_hi, width: 8
    input :x_reg, width: 8
    input :y_reg, width: 8
    input :pc, width: 16
    input :sp, width: 8
    input :indirect_lo, width: 8
    input :indirect_hi, width: 8

    output :eff_addr, width: 16
    output :page_cross
    output :is_zero_page

    # Behavior block for combinational synthesis
    behavior do
      # Calculate intermediate values
      abs_addr = local(:abs_addr, cat(operand_hi, operand_lo), width: 16)
      abs_x_addr = local(:abs_x_addr, abs_addr + cat(lit(0, width: 8), x_reg), width: 16)
      abs_y_addr = local(:abs_y_addr, abs_addr + cat(lit(0, width: 8), y_reg), width: 16)
      ind_addr = local(:ind_addr, cat(indirect_hi, indirect_lo), width: 16)
      ind_y_addr = local(:ind_y_addr, ind_addr + cat(lit(0, width: 8), y_reg), width: 16)

      # Relative address with sign extension
      # rel_addr = pc + sign_extend(operand_lo)
      rel_offset = local(:rel_offset,
        mux(operand_lo[7],
            cat(lit(0xFF, width: 8), operand_lo),  # Negative
            cat(lit(0, width: 8), operand_lo)),    # Positive
        width: 16)
      rel_addr = local(:rel_addr, pc + rel_offset, width: 16)

      stack_addr = local(:stack_addr, cat(lit(1, width: 8), sp), width: 16)

      # eff_addr: case select based on mode
      eff_addr <= case_select(mode, {
        MODE_IMPLIED => lit(0, width: 16),
        MODE_ACCUMULATOR => lit(0, width: 16),
        MODE_IMMEDIATE => lit(0, width: 16),
        MODE_ZERO_PAGE => cat(lit(0, width: 8), operand_lo),
        MODE_ZERO_PAGE_X => cat(lit(0, width: 8), (operand_lo + x_reg)[7..0]),
        MODE_ZERO_PAGE_Y => cat(lit(0, width: 8), (operand_lo + y_reg)[7..0]),
        MODE_ABSOLUTE => abs_addr,
        MODE_ABSOLUTE_X => abs_x_addr,
        MODE_ABSOLUTE_Y => abs_y_addr,
        MODE_INDIRECT => ind_addr,
        MODE_INDEXED_IND => ind_addr,
        MODE_INDIRECT_IDX => ind_y_addr,
        MODE_RELATIVE => rel_addr,
        MODE_STACK => stack_addr
      }, default: 0)

      # page_cross: only for certain modes
      page_cross <= case_select(mode, {
        MODE_ABSOLUTE_X => abs_x_addr[15..8] != operand_hi,
        MODE_ABSOLUTE_Y => abs_y_addr[15..8] != operand_hi,
        MODE_INDIRECT_IDX => ind_y_addr[15..8] != indirect_hi,
        MODE_RELATIVE => rel_addr[15..8] != pc[15..8]
      }, default: 0)

      # is_zero_page: only for zero page modes
      is_zero_page <= case_select(mode, {
        MODE_ZERO_PAGE => lit(1, width: 1),
        MODE_ZERO_PAGE_X => lit(1, width: 1),
        MODE_ZERO_PAGE_Y => lit(1, width: 1)
      }, default: 0)
    end

    def self.verilog_module_name
      'mos6502_address_generator'
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: verilog_module_name))
    end
  end
end
