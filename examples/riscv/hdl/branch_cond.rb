# RV32I Branch Condition Logic
# Evaluates branch conditions based on rs1 and rs2 values
# Supports BEQ, BNE, BLT, BGE, BLTU, BGEU

require_relative '../../../lib/rhdl'
require_relative '../../../lib/rhdl/dsl/behavior'
require_relative 'constants'

module RISCV
  class BranchCond < RHDL::HDL::SimComponent
    include RHDL::DSL::Behavior

    port_input :rs1_data, width: 32  # Source register 1 data
    port_input :rs2_data, width: 32  # Source register 2 data
    port_input :funct3, width: 3     # Branch condition type

    port_output :branch_taken        # Branch should be taken

    behavior do
      # Compute comparison results
      eq = rs1_data == rs2_data

      # Signed comparison: check signs and then magnitudes
      rs1_sign = rs1_data[31]
      rs2_sign = rs2_data[31]

      # Signed less than: if signs differ, negative is less
      # If signs same, compare magnitudes (unsigned comparison)
      signed_lt = local(:signed_lt,
        mux(rs1_sign != rs2_sign,
          rs1_sign,  # Different signs: rs1 < rs2 if rs1 is negative
          rs1_data < rs2_data  # Same signs: unsigned compare
        ), width: 1)

      # Unsigned less than
      unsigned_lt = rs1_data < rs2_data

      # Branch condition evaluation
      branch_taken <= case_select(funct3, {
        Funct3::BEQ  => eq,                   # Equal
        Funct3::BNE  => ~eq,                  # Not equal
        Funct3::BLT  => signed_lt,            # Less than (signed)
        Funct3::BGE  => ~signed_lt,           # Greater or equal (signed)
        Funct3::BLTU => unsigned_lt,          # Less than (unsigned)
        Funct3::BGEU => ~unsigned_lt          # Greater or equal (unsigned)
      }, default: lit(0, width: 1))
    end

    def self.verilog_module_name
      'riscv_branch_cond'
    end

    def self.to_verilog
      RHDL::Export::Verilog.generate(to_ir(top_name: verilog_module_name))
    end
  end
end
