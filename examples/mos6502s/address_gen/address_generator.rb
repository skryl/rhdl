# MOS 6502 Address Generator - Synthesizable DSL Version
# Computes effective addresses for all 6502 addressing modes
# Combinational logic - synthesized from behavior DSL

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

    # Propagate for simulation
    def propagate
      mode_val = in_val(:mode) & 0x0F
      operand_lo_val = in_val(:operand_lo) & 0xFF
      operand_hi_val = in_val(:operand_hi) & 0xFF
      x = in_val(:x_reg) & 0xFF
      y = in_val(:y_reg) & 0xFF
      pc_val = in_val(:pc) & 0xFFFF
      sp_val = in_val(:sp) & 0xFF
      ind_lo = in_val(:indirect_lo) & 0xFF
      ind_hi = in_val(:indirect_hi) & 0xFF

      eff_addr = 0
      page_cross = 0
      is_zp = 0

      case mode_val
      when MODE_IMPLIED, MODE_ACCUMULATOR, MODE_IMMEDIATE
        eff_addr = 0

      when MODE_ZERO_PAGE
        eff_addr = operand_lo_val
        is_zp = 1

      when MODE_ZERO_PAGE_X
        eff_addr = (operand_lo_val + x) & 0xFF
        is_zp = 1

      when MODE_ZERO_PAGE_Y
        eff_addr = (operand_lo_val + y) & 0xFF
        is_zp = 1

      when MODE_ABSOLUTE
        eff_addr = (operand_hi_val << 8) | operand_lo_val

      when MODE_ABSOLUTE_X
        base = (operand_hi_val << 8) | operand_lo_val
        eff_addr = (base + x) & 0xFFFF
        page_cross = ((eff_addr >> 8) != operand_hi_val) ? 1 : 0

      when MODE_ABSOLUTE_Y
        base = (operand_hi_val << 8) | operand_lo_val
        eff_addr = (base + y) & 0xFFFF
        page_cross = ((eff_addr >> 8) != operand_hi_val) ? 1 : 0

      when MODE_INDIRECT
        eff_addr = (ind_hi << 8) | ind_lo

      when MODE_INDEXED_IND
        eff_addr = (ind_hi << 8) | ind_lo

      when MODE_INDIRECT_IDX
        base = (ind_hi << 8) | ind_lo
        eff_addr = (base + y) & 0xFFFF
        page_cross = ((eff_addr >> 8) != ind_hi) ? 1 : 0

      when MODE_RELATIVE
        offset = operand_lo_val
        signed_offset = (offset & 0x80) != 0 ? (offset - 256) : offset
        target = (pc_val + signed_offset) & 0xFFFF
        eff_addr = target
        page_cross = ((target >> 8) != (pc_val >> 8)) ? 1 : 0

      when MODE_STACK
        eff_addr = STACK_BASE | sp_val
      end

      out_set(:eff_addr, eff_addr)
      out_set(:page_cross, page_cross)
      out_set(:is_zero_page, is_zp)
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: 'mos6502s_address_generator'))
    end
  end
end
