# MOS 6502 Address Latch - Synthesizable DSL Version
# 16-bit address latch with byte-wise and full loading

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module MOS6502S
  # Address Latch - Synthesizable via Sequential DSL
  # Uses internal registers and derives outputs combinationally
  class AddressLatch < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    port_input :clk
    port_input :rst
    port_input :load_lo
    port_input :load_hi
    port_input :load_full
    port_input :data_in, width: 8
    port_input :addr_in, width: 16

    # Internal registers (exposed as outputs for now)
    port_output :addr_lo, width: 8
    port_output :addr_hi, width: 8
    port_output :addr, width: 16

    def initialize(name = nil)
      @addr_lo_reg = 0
      @addr_hi_reg = 0
      super(name)
    end

    # Sequential block for internal registers
    # Priority: load_full > load_lo/load_hi > hold
    sequential clock: :clk, reset: :rst, reset_values: { addr_lo: 0, addr_hi: 0 } do
      addr_lo <= mux(load_full, addr_in[7..0],
                    mux(load_lo, data_in, addr_lo))
      addr_hi <= mux(load_full, addr_in[15..8],
                    mux(load_hi, data_in, addr_hi))
    end

    # Combinational output: 16-bit address from hi/lo
    behavior do
      addr <= cat(addr_hi, addr_lo)
    end

    # Override propagate to maintain internal state for testing
    def propagate
      if rising_edge?
        if in_val(:rst) == 1
          @addr_lo_reg = 0
          @addr_hi_reg = 0
        elsif in_val(:load_full) == 1
          addr = in_val(:addr_in) & 0xFFFF
          @addr_lo_reg = addr & 0xFF
          @addr_hi_reg = (addr >> 8) & 0xFF
        else
          data = in_val(:data_in) & 0xFF
          @addr_lo_reg = data if in_val(:load_lo) == 1
          @addr_hi_reg = data if in_val(:load_hi) == 1
        end
      end

      out_set(:addr, (@addr_hi_reg << 8) | @addr_lo_reg)
      out_set(:addr_lo, @addr_lo_reg)
      out_set(:addr_hi, @addr_hi_reg)
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: 'mos6502s_address_latch'))
    end
  end
end
