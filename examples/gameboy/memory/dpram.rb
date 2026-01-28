# Dual-Port RAM
# Corresponds to: reference/rtl/dpram.vhd
#
# True dual-port RAM with independent read/write ports.
# Used for VRAM, WRAM, etc.
#
# This is a simplified placeholder. The Game Boy uses various memory
# sizes instantiated as needed (VRAM 8KB, WRAM 8KB, etc.)

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module GameBoy
  class DPRAM < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # Fixed 8KB configuration (common for VRAM/WRAM)
    ADDR_WIDTH = 13
    DATA_WIDTH = 8
    DEPTH = 8192

    # Port A
    input :clock_a
    input :address_a, width: ADDR_WIDTH
    input :wren_a, default: 0
    input :data_a, width: DATA_WIDTH
    output :q_a, width: DATA_WIDTH

    # Port B
    input :clock_b
    input :address_b, width: ADDR_WIDTH
    input :wren_b, default: 0
    input :data_b, width: DATA_WIDTH
    output :q_b, width: DATA_WIDTH

    # Internal registers for output
    wire :q_a_reg, width: DATA_WIDTH
    wire :q_b_reg, width: DATA_WIDTH

    behavior do
      q_a <= q_a_reg
      q_b <= q_b_reg
    end

    sequential clock: :clock_a, reset_values: { q_a_reg: 0 } do
      # Placeholder - actual memory behavior in simulator
      q_a_reg <= q_a_reg
    end

    sequential clock: :clock_b, reset_values: { q_b_reg: 0 } do
      q_b_reg <= q_b_reg
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
