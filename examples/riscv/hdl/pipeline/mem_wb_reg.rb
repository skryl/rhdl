# MEM/WB Pipeline Register
# Holds memory read data and ALU result for write-back

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RISCV
  module Pipeline
    class MEM_WB_Reg < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :clk
      input :rst

      # Data from MEM stage
      input :alu_result_in, width: 32
      input :mem_data_in, width: 32
      input :rd_addr_in, width: 5
      input :pc_plus4_in, width: 32    # For JAL/JALR

      # Control signals from MEM stage
      input :reg_write_in
      input :mem_to_reg_in
      input :jump_in

      # Outputs to WB stage
      output :alu_result_out, width: 32
      output :mem_data_out, width: 32
      output :rd_addr_out, width: 5
      output :pc_plus4_out, width: 32
      output :wb_data_out, width: 32  # Pre-computed write-back data

      # Control outputs
      output :reg_write_out
      output :mem_to_reg_out
      output :jump_out

      sequential clock: :clk, reset: :rst, reset_values: {
        alu_result_out: 0, mem_data_out: 0, rd_addr_out: 0, pc_plus4_out: 4,
        wb_data_out: 0, reg_write_out: 0, mem_to_reg_out: 0, jump_out: 0
      } do
        alu_result_out <= alu_result_in
        mem_data_out <= mem_data_in
        rd_addr_out <= rd_addr_in
        pc_plus4_out <= pc_plus4_in

        reg_write_out <= reg_write_in
        mem_to_reg_out <= mem_to_reg_in
        jump_out <= jump_in

        # Pre-compute write-back data selection inside the register
        # This ensures wb_data is available as soon as the register propagates
        wb_data_out <= mux(jump_in, pc_plus4_in,
                        mux(mem_to_reg_in, mem_data_in, alu_result_in))
      end

    end
  end
end
