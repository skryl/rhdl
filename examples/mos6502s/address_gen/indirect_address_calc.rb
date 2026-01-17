# MOS 6502 Indirect Address Calculator - Synthesizable DSL Version
# Helper for computing indirect address fetch locations

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative 'address_generator'

module MOS6502S
  # Helper for computing indirect address fetch locations - Synthesizable via Behavior DSL
  class IndirectAddressCalc < RHDL::HDL::SimComponent
    include RHDL::DSL::Behavior

    # Mode constants
    MODE_INDIRECT    = 0x09
    MODE_INDEXED_IND = 0x0A
    MODE_INDIRECT_IDX = 0x0B

    port_input :mode, width: 4
    port_input :operand_lo, width: 8
    port_input :operand_hi, width: 8
    port_input :x_reg, width: 8

    port_output :ptr_addr_lo, width: 16
    port_output :ptr_addr_hi, width: 16

    # Behavior block for combinational synthesis
    behavior do
      # Helper calculations
      abs_addr = local(:abs_addr, cat(operand_hi, operand_lo), width: 16)
      zp_addr_x = local(:zp_addr_x, (operand_lo + x_reg)[7..0], width: 8)

      # ptr_addr_lo: depends on mode
      ptr_addr_lo <= case_select(mode, {
        MODE_INDIRECT => abs_addr,
        MODE_INDEXED_IND => cat(lit(0, width: 8), zp_addr_x),
        MODE_INDIRECT_IDX => cat(lit(0, width: 8), operand_lo)
      }, default: 0)

      # ptr_addr_hi: depends on mode with 6502 page wrap bug handling
      # For MODE_INDIRECT: if low byte is $FF, high byte comes from $xx00
      ind_hi_normal = local(:ind_hi_normal, abs_addr + lit(1, width: 16), width: 16)
      ind_hi_buggy = local(:ind_hi_buggy, cat(operand_hi, lit(0, width: 8)), width: 16)
      is_page_wrap = operand_lo == lit(0xFF, width: 8)

      ptr_addr_hi <= case_select(mode, {
        MODE_INDIRECT => mux(is_page_wrap, ind_hi_buggy, ind_hi_normal),
        MODE_INDEXED_IND => cat(lit(0, width: 8), (zp_addr_x + lit(1, width: 8))[7..0]),
        MODE_INDIRECT_IDX => cat(lit(0, width: 8), (operand_lo + lit(1, width: 8))[7..0])
      }, default: 0)
    end

    # Propagate for simulation
    def propagate
      mode_val = in_val(:mode) & 0x0F
      operand_lo_val = in_val(:operand_lo) & 0xFF
      operand_hi_val = in_val(:operand_hi) & 0xFF
      x = in_val(:x_reg) & 0xFF

      ptr_lo = 0
      ptr_hi = 0

      case mode_val
      when MODE_INDIRECT
        base = (operand_hi_val << 8) | operand_lo_val
        ptr_lo = base
        ptr_hi = ((base & 0xFF) == 0xFF) ? (base & 0xFF00) : ((base + 1) & 0xFFFF)

      when MODE_INDEXED_IND
        zp_addr = (operand_lo_val + x) & 0xFF
        ptr_lo = zp_addr
        ptr_hi = (zp_addr + 1) & 0xFF

      when MODE_INDIRECT_IDX
        ptr_lo = operand_lo_val
        ptr_hi = (operand_lo_val + 1) & 0xFF
      end

      out_set(:ptr_addr_lo, ptr_lo)
      out_set(:ptr_addr_hi, ptr_hi)
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: 'mos6502s_indirect_addr_calc'))
    end
  end
end
