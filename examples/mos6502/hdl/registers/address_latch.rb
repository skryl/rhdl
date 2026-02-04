# MOS 6502 Address Latch - Synthesizable DSL Version
# 16-bit address latch with byte-wise and full loading

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module MOS6502
      # Address Latch - Synthesizable via Sequential DSL
      # Uses internal registers and derives outputs combinationally
      class AddressLatch < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :rst
    input :load_lo
    input :load_hi
    input :load_full
    input :data_in, width: 8
    input :addr_in, width: 16

    # Internal registers (exposed as outputs for now)
    output :addr_lo, width: 8
    output :addr_hi, width: 8
    output :addr, width: 16

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

    end
  end
end
end
