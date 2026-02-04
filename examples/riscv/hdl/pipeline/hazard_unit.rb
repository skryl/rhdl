# Hazard Detection Unit
# Detects data hazards requiring pipeline stalls (load-use hazard)
# and control hazards requiring flushes (branches/jumps)

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'

module RHDL
  module Examples
    module RISCV
      module Pipeline
        class HazardUnit < RHDL::HDL::Component
      include RHDL::DSL::Behavior

      # From ID stage (current instruction being decoded)
      input :id_rs1_addr, width: 5
      input :id_rs2_addr, width: 5

      # From ID/EX register (instruction in EX stage)
      input :ex_rd_addr, width: 5
      input :ex_mem_read             # Load instruction in EX

      # From EX/MEM register (for branch/jump detection)
      input :mem_rd_addr, width: 5
      input :mem_mem_read            # Load instruction in MEM

      # Branch/jump signals
      input :branch_taken            # Branch is taken
      input :jump                    # Jump instruction

      # Outputs
      output :stall                  # Stall IF and ID stages
      output :flush_if_id            # Flush IF/ID register
      output :flush_id_ex            # Flush ID/EX register

      behavior do
        # Load-use hazard detection:
        # If EX stage has a load that writes to a register we need in ID
        rs1_used = id_rs1_addr != lit(0, width: 5)
        rs2_used = id_rs2_addr != lit(0, width: 5)

        # Hazard when load in EX writes to rs1 or rs2 of instruction in ID
        load_use_hazard = ex_mem_read & (
          (rs1_used & (ex_rd_addr == id_rs1_addr)) |
          (rs2_used & (ex_rd_addr == id_rs2_addr))
        )

        # Stall on load-use hazard
        stall <= load_use_hazard

        # Flush IF/ID on branch taken or jump
        flush_if_id <= branch_taken | jump

        # Flush ID/EX on branch taken, jump, or load-use stall
        # (Insert bubble in EX when stalling)
        flush_id_ex <= branch_taken | jump | load_use_hazard
      end

        end
      end
    end
  end
end
