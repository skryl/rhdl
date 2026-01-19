# RV32I Program Counter
# Sequential component with load and increment control
# Supports branching, jumping, and sequential execution

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative '../../../lib/rhdl/dsl/sequential'

module RISCV
  class ProgramCounter < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    # Default reset vector
    RESET_VECTOR = 0x00000000

    input :clk
    input :rst

    input :pc_next, width: 32   # Next PC value (computed by datapath)
    input :pc_we                # PC write enable

    output :pc, width: 32       # Current PC value

    sequential clock: :clk, reset: :rst, reset_values: { pc: RESET_VECTOR } do
      pc <= mux(pc_we, pc_next, pc)
    end

    # Direct access for testing
    def read_pc
      read_reg(:pc)
    end

    def write_pc(value)
      write_reg(:pc, value & 0xFFFFFFFF)
    end

  end
end
