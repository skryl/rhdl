# Single-Port RAM
# Corresponds to: reference/rtl/spram.vhd
#
# Simple single-port RAM with single clock domain.
#
# This is a simplified placeholder. The Game Boy uses various memory
# sizes instantiated as needed.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module GameBoy
  class SPRAM < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # Fixed 8KB configuration
    ADDR_WIDTH = 13
    DATA_WIDTH = 8
    DEPTH = 8192

    input :clock
    input :address, width: ADDR_WIDTH
    input :wren, default: 0
    input :data_in, width: DATA_WIDTH
    output :data_out, width: DATA_WIDTH

    # Internal register
    wire :data_out_reg, width: DATA_WIDTH

    behavior do
      data_out <= data_out_reg
    end

    sequential clock: :clock, reset_values: { data_out_reg: 0 } do
      # Placeholder - actual memory behavior in simulator
      data_out_reg <= data_out_reg
    end

    # Memory is managed at instance level for simulation
    def initialize(name = nil, **kwargs)
      super
      @ram = Array.new(DEPTH, 0)
    end

    def read_mem(addr)
      @ram[addr & (DEPTH - 1)] || 0
    end

    def write_mem(addr, data)
      @ram[addr & (DEPTH - 1)] = data & 0xFF
    end
  end
end
