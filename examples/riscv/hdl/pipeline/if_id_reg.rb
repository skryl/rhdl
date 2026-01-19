# IF/ID Pipeline Register
# Holds instruction and PC from Instruction Fetch stage

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RISCV
  module Pipeline
    class IF_ID_Reg < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :clk
      input :rst
      input :stall              # Stall signal from hazard unit
      input :flush              # Flush signal (branch taken)

      # Inputs from IF stage
      input :pc_in, width: 32
      input :inst_in, width: 32
      input :pc_plus4_in, width: 32

      # Outputs to ID stage
      output :pc_out, width: 32
      output :inst_out, width: 32
      output :pc_plus4_out, width: 32

      sequential clock: :clk, reset: :rst, reset_values: {
        pc_out: 0,
        inst_out: 0x00000013,  # NOP (ADDI x0, x0, 0)
        pc_plus4_out: 4
      } do
        # On flush, insert NOP
        # On stall, hold current values
        # Otherwise, latch new values
        pc_out <= mux(flush, lit(0, width: 32),
                   mux(stall, pc_out, pc_in))
        inst_out <= mux(flush, lit(0x00000013, width: 32),
                     mux(stall, inst_out, inst_in))
        pc_plus4_out <= mux(flush, lit(4, width: 32),
                         mux(stall, pc_plus4_out, pc_plus4_in))
      end

    end
  end
end
