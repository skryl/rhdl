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

      port_input :clk
      port_input :rst

      # Data from MEM stage
      port_input :alu_result_in, width: 32
      port_input :mem_data_in, width: 32
      port_input :rd_addr_in, width: 5
      port_input :pc_plus4_in, width: 32    # For JAL/JALR

      # Control signals from MEM stage
      port_input :reg_write_in
      port_input :mem_to_reg_in
      port_input :jump_in

      # Outputs to WB stage
      port_output :alu_result_out, width: 32
      port_output :mem_data_out, width: 32
      port_output :rd_addr_out, width: 5
      port_output :pc_plus4_out, width: 32

      # Control outputs
      port_output :reg_write_out
      port_output :mem_to_reg_out
      port_output :jump_out

      sequential clock: :clk, reset: :rst, reset_values: {
        alu_result_out: 0, mem_data_out: 0, rd_addr_out: 0, pc_plus4_out: 4,
        reg_write_out: 0, mem_to_reg_out: 0, jump_out: 0
      } do
        alu_result_out <= alu_result_in
        mem_data_out <= mem_data_in
        rd_addr_out <= rd_addr_in
        pc_plus4_out <= pc_plus4_in

        reg_write_out <= reg_write_in
        mem_to_reg_out <= mem_to_reg_in
        jump_out <= jump_in
      end

      def self.verilog_module_name
        'riscv_mem_wb_reg'
      end

      def self.to_verilog
        RHDL::Export::Verilog.generate(to_ir(top_name: verilog_module_name))
      end
    end
  end
end
