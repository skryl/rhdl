# Forwarding Unit
# Implements data forwarding (bypassing) to resolve RAW hazards
# without stalling when possible

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../constants'

module RHDL
  module Examples
    module RISCV
      module Pipeline
        # Forward source selection
        module ForwardSel
      NONE    = 0  # No forwarding, use register file
      EX_MEM  = 1  # Forward from EX/MEM (ALU result)
      MEM_WB  = 2  # Forward from MEM/WB (memory or ALU result)
    end

    class ForwardingUnit < RHDL::HDL::Component
      include RHDL::DSL::Behavior

      # Source registers in EX stage (from ID/EX)
      input :ex_rs1_addr, width: 5
      input :ex_rs2_addr, width: 5

      # Destination from EX/MEM stage
      input :mem_rd_addr, width: 5
      input :mem_reg_write

      # Destination from MEM/WB stage
      input :wb_rd_addr, width: 5
      input :wb_reg_write

      # Forward selection outputs
      # 00 = no forward (use register file value)
      # 01 = forward from EX/MEM (ALU result)
      # 10 = forward from MEM/WB (ALU result or memory data)
      output :forward_a, width: 2
      output :forward_b, width: 2

      behavior do
        # Forward A (rs1)
        # Priority: EX/MEM > MEM/WB (more recent result wins)
        forward_a_from_mem = mem_reg_write &
                             (mem_rd_addr != lit(0, width: 5)) &
                             (mem_rd_addr == ex_rs1_addr)

        forward_a_from_wb = wb_reg_write &
                            (wb_rd_addr != lit(0, width: 5)) &
                            (wb_rd_addr == ex_rs1_addr) &
                            ~forward_a_from_mem  # MEM has priority

        forward_a <= mux(forward_a_from_mem, lit(ForwardSel::EX_MEM, width: 2),
                      mux(forward_a_from_wb, lit(ForwardSel::MEM_WB, width: 2),
                        lit(ForwardSel::NONE, width: 2)))

        # Forward B (rs2)
        forward_b_from_mem = mem_reg_write &
                             (mem_rd_addr != lit(0, width: 5)) &
                             (mem_rd_addr == ex_rs2_addr)

        forward_b_from_wb = wb_reg_write &
                            (wb_rd_addr != lit(0, width: 5)) &
                            (wb_rd_addr == ex_rs2_addr) &
                            ~forward_b_from_mem

        forward_b <= mux(forward_b_from_mem, lit(ForwardSel::EX_MEM, width: 2),
                      mux(forward_b_from_wb, lit(ForwardSel::MEM_WB, width: 2),
                        lit(ForwardSel::NONE, width: 2)))
      end

        end
      end
    end
  end
end
