# EX/MEM Pipeline Register
# Holds ALU result and memory control signals

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module RISCV
      module Pipeline
        class EX_MEM_Reg < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :clk
      input :rst

      # Data from EX stage
      input :alu_result_in, width: 32
      input :rs2_data_in, width: 32    # Store data
      input :rd_addr_in, width: 5
      input :pc_plus4_in, width: 32    # For JAL/JALR
      input :funct3_in, width: 3       # For load/store size
      input :funct7_in, width: 7
      input :opcode_in, width: 7
      input :rs2_addr_in, width: 5

      # Control signals from EX stage
      input :reg_write_in
      input :mem_read_in
      input :mem_write_in
      input :mem_to_reg_in
      input :jump_in                   # JAL/JALR writes PC+4

      # Outputs to MEM stage
      output :alu_result_out, width: 32
      output :rs2_data_out, width: 32
      output :rd_addr_out, width: 5
      output :pc_plus4_out, width: 32
      output :funct3_out, width: 3
      output :funct7_out, width: 7
      output :opcode_out, width: 7
      output :rs2_addr_out, width: 5

      # Control outputs
      output :reg_write_out
      output :mem_read_out
      output :mem_write_out
      output :mem_to_reg_out
      output :jump_out

      sequential clock: :clk, reset: :rst, reset_values: {
        alu_result_out: 0, rs2_data_out: 0, rd_addr_out: 0,
        pc_plus4_out: 4, funct3_out: 0, funct7_out: 0, opcode_out: 0, rs2_addr_out: 0,
        reg_write_out: 0, mem_read_out: 0, mem_write_out: 0,
        mem_to_reg_out: 0, jump_out: 0
      } do
        alu_result_out <= alu_result_in
        rs2_data_out <= rs2_data_in
        rd_addr_out <= rd_addr_in
        pc_plus4_out <= pc_plus4_in
        funct3_out <= funct3_in
        funct7_out <= funct7_in
        opcode_out <= opcode_in
        rs2_addr_out <= rs2_addr_in

        reg_write_out <= reg_write_in
        mem_read_out <= mem_read_in
        mem_write_out <= mem_write_in
        mem_to_reg_out <= mem_to_reg_in
        jump_out <= jump_in
      end

        end
      end
    end
  end
end
