# MOS 6502 Address Generation Unit
# Computes effective addresses for all 6502 addressing modes

module MOS6502
  class AddressGenerator < RHDL::HDL::SimComponent
    # Addressing mode constants
    MODE_IMPLIED     = 0x00  # No address needed (e.g., TAX)
    MODE_ACCUMULATOR = 0x01  # Operate on accumulator (e.g., ASL A)
    MODE_IMMEDIATE   = 0x02  # Immediate value (#$nn)
    MODE_ZERO_PAGE   = 0x03  # Zero page ($00nn)
    MODE_ZERO_PAGE_X = 0x04  # Zero page + X (($nn + X) & 0xFF)
    MODE_ZERO_PAGE_Y = 0x05  # Zero page + Y (($nn + Y) & 0xFF)
    MODE_ABSOLUTE    = 0x06  # Absolute address ($nnnn)
    MODE_ABSOLUTE_X  = 0x07  # Absolute + X
    MODE_ABSOLUTE_Y  = 0x08  # Absolute + Y
    MODE_INDIRECT    = 0x09  # Indirect (JMP only)
    MODE_INDEXED_IND = 0x0A  # Indexed indirect ($nn,X)
    MODE_INDIRECT_IDX= 0x0B  # Indirect indexed ($nn),Y
    MODE_RELATIVE    = 0x0C  # Relative (branches)
    MODE_STACK       = 0x0D  # Stack operations

    STACK_BASE = 0x0100

    def initialize(name = nil)
      super(name)
    end

    def setup_ports
      # Inputs
      input :mode, width: 4           # Addressing mode selector
      input :operand_lo, width: 8     # Low byte of operand
      input :operand_hi, width: 8     # High byte of operand (for absolute)
      input :x_reg, width: 8          # X register value
      input :y_reg, width: 8          # Y register value
      input :pc, width: 16            # Program counter (for relative)
      input :sp, width: 8             # Stack pointer
      input :indirect_lo, width: 8    # Low byte read from indirect address
      input :indirect_hi, width: 8    # High byte read from indirect address

      # Outputs
      output :eff_addr, width: 16     # Effective address
      output :page_cross             # Set if page boundary crossed
      output :is_zero_page           # Address is in zero page
    end

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
      when MODE_IMPLIED, MODE_ACCUMULATOR
        # No address calculation needed
        eff_addr = 0

      when MODE_IMMEDIATE
        # Immediate: operand is the value, address is PC+1
        # But the datapath handles this specially
        eff_addr = 0

      when MODE_ZERO_PAGE
        # Zero page: address is $00xx
        eff_addr = operand_lo
        is_zp = 1

      when MODE_ZERO_PAGE_X
        # Zero page,X: address wraps within zero page
        eff_addr = (operand_lo + x) & 0xFF
        is_zp = 1

      when MODE_ZERO_PAGE_Y
        # Zero page,Y: address wraps within zero page
        eff_addr = (operand_lo + y) & 0xFF
        is_zp = 1

      when MODE_ABSOLUTE
        # Absolute: 16-bit address
        eff_addr = (operand_hi << 8) | operand_lo

      when MODE_ABSOLUTE_X
        # Absolute,X: may cross page
        base = (operand_hi << 8) | operand_lo
        eff_addr = (base + x) & 0xFFFF
        page_cross = (eff_addr >> 8) != operand_hi ? 1 : 0

      when MODE_ABSOLUTE_Y
        # Absolute,Y: may cross page
        base = (operand_hi << 8) | operand_lo
        eff_addr = (base + y) & 0xFFFF
        page_cross = (eff_addr >> 8) != operand_hi ? 1 : 0

      when MODE_INDIRECT
        # Indirect: address comes from two bytes at operand address
        # Note: 6502 bug - doesn't cross page boundary for high byte
        eff_addr = (ind_hi << 8) | ind_lo

      when MODE_INDEXED_IND
        # Indexed Indirect ($nn,X):
        # Read address from (operand + X) in zero page
        eff_addr = (ind_hi << 8) | ind_lo

      when MODE_INDIRECT_IDX
        # Indirect Indexed ($nn),Y:
        # Read address from operand in zero page, then add Y
        base = (ind_hi << 8) | ind_lo
        eff_addr = (base + y) & 0xFFFF
        page_cross = (eff_addr >> 8) != ind_hi ? 1 : 0

      when MODE_RELATIVE
        # Relative: signed 8-bit offset from PC+2
        offset = operand_lo
        # Sign extend
        if (offset & 0x80) != 0
          offset = offset - 256
        end
        target = (pc + offset) & 0xFFFF
        eff_addr = target
        # Page cross if high bytes differ
        page_cross = (target >> 8) != (pc >> 8) ? 1 : 0

      when MODE_STACK
        # Stack: address is $0100 + SP
        eff_addr = STACK_BASE | sp
      end

      out_set(:eff_addr, eff_addr)
      out_set(:page_cross, page_cross)
      out_set(:is_zero_page, is_zp)
    end
  end

  # Helper component for computing indirect address fetch locations
  class IndirectAddressCalc < RHDL::HDL::SimComponent
    def initialize(name = nil)
      super(name)
    end

    def setup_ports
      input :mode, width: 4
      input :operand_lo, width: 8
      input :operand_hi, width: 8
      input :x_reg, width: 8

      # Address to fetch the low byte of indirect pointer
      output :ptr_addr_lo, width: 16
      # Address to fetch the high byte of indirect pointer
      output :ptr_addr_hi, width: 16
    end

    def propagate
      mode = in_val(:mode) & 0x0F
      operand_lo = in_val(:operand_lo) & 0xFF
      operand_hi = in_val(:operand_hi) & 0xFF
      x = in_val(:x_reg) & 0xFF

      ptr_lo = 0
      ptr_hi = 0

      case mode
      when AddressGenerator::MODE_INDIRECT
        # JMP indirect - read from operand address
        base = (operand_hi << 8) | operand_lo
        ptr_lo = base
        # 6502 bug: if low byte is $FF, high byte comes from xx00
        if (base & 0xFF) == 0xFF
          ptr_hi = base & 0xFF00
        else
          ptr_hi = (base + 1) & 0xFFFF
        end

      when AddressGenerator::MODE_INDEXED_IND
        # ($nn,X) - read from (operand + X) in zero page
        zp_addr = (operand_lo + x) & 0xFF
        ptr_lo = zp_addr
        ptr_hi = (zp_addr + 1) & 0xFF  # Wraps in zero page

      when AddressGenerator::MODE_INDIRECT_IDX
        # ($nn),Y - read from operand in zero page
        ptr_lo = operand_lo
        ptr_hi = (operand_lo + 1) & 0xFF  # Wraps in zero page
      end

      out_set(:ptr_addr_lo, ptr_lo)
      out_set(:ptr_addr_hi, ptr_hi)
    end
  end
end
