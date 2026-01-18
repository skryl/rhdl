# EX/MEM Pipeline Register
# Holds ALU result and memory control signals

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RISCV
  module Pipeline
    class EX_MEM_Reg < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      port_input :clk
      port_input :rst

      # Data from EX stage
      port_input :alu_result_in, width: 32
      port_input :rs2_data_in, width: 32    # Store data
      port_input :rd_addr_in, width: 5
      port_input :pc_plus4_in, width: 32    # For JAL/JALR
      port_input :funct3_in, width: 3       # For load/store size

      # Control signals from EX stage
      port_input :reg_write_in
      port_input :mem_read_in
      port_input :mem_write_in
      port_input :mem_to_reg_in
      port_input :jump_in                   # JAL/JALR writes PC+4

      # Outputs to MEM stage
      port_output :alu_result_out, width: 32
      port_output :rs2_data_out, width: 32
      port_output :rd_addr_out, width: 5
      port_output :pc_plus4_out, width: 32
      port_output :funct3_out, width: 3

      # Control outputs
      port_output :reg_write_out
      port_output :mem_read_out
      port_output :mem_write_out
      port_output :mem_to_reg_out
      port_output :jump_out

      sequential clock: :clk, reset: :rst, reset_values: {
        alu_result_out: 0, rs2_data_out: 0, rd_addr_out: 0,
        pc_plus4_out: 4, funct3_out: 0,
        reg_write_out: 0, mem_read_out: 0, mem_write_out: 0,
        mem_to_reg_out: 0, jump_out: 0
      } do
        alu_result_out <= alu_result_in
        rs2_data_out <= rs2_data_in
        rd_addr_out <= rd_addr_in
        pc_plus4_out <= pc_plus4_in
        funct3_out <= funct3_in

        reg_write_out <= reg_write_in
        mem_read_out <= mem_read_in
        mem_write_out <= mem_write_in
        mem_to_reg_out <= mem_to_reg_in
        jump_out <= jump_in
      end

      def self.verilog_module_name
        'riscv_ex_mem_reg'
      end

      def self.to_verilog
        RHDL::Export::Verilog.generate(to_ir(top_name: verilog_module_name))
      end
    end
  end
end
