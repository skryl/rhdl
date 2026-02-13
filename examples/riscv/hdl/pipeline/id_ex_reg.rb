# ID/EX Pipeline Register
# Holds decoded instruction data and control signals

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../../../../lib/rhdl/dsl/sequential'

module RHDL
  module Examples
    module RISCV
      module Pipeline
        class ID_EX_Reg < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :clk
      input :rst
      input :flush              # Flush on branch/jump

      # Data from ID stage
      input :pc_in, width: 32
      input :pc_plus4_in, width: 32
      input :rs1_data_in, width: 32
      input :rs2_data_in, width: 32
      input :imm_in, width: 32
      input :rs1_addr_in, width: 5
      input :rs2_addr_in, width: 5
      input :rd_addr_in, width: 5
      input :funct3_in, width: 3
      input :funct7_in, width: 7
      input :opcode_in, width: 7
      input :inst_page_fault_in

      # Control signals from ID stage
      input :alu_op_in, width: 5
      input :alu_src_in           # 0=rs2, 1=imm
      input :reg_write_in
      input :mem_read_in
      input :mem_write_in
      input :mem_to_reg_in
      input :branch_in
      input :jump_in
      input :jalr_in

      # Outputs to EX stage
      output :pc_out, width: 32
      output :pc_plus4_out, width: 32
      output :rs1_data_out, width: 32
      output :rs2_data_out, width: 32
      output :imm_out, width: 32
      output :rs1_addr_out, width: 5
      output :rs2_addr_out, width: 5
      output :rd_addr_out, width: 5
      output :funct3_out, width: 3
      output :funct7_out, width: 7
      output :opcode_out, width: 7
      output :inst_page_fault_out

      # Control outputs
      output :alu_op_out, width: 5
      output :alu_src_out
      output :reg_write_out
      output :mem_read_out
      output :mem_write_out
      output :mem_to_reg_out
      output :branch_out
      output :jump_out
      output :jalr_out

      sequential clock: :clk, reset: :rst, reset_values: {
        pc_out: 0, pc_plus4_out: 4,
        rs1_data_out: 0, rs2_data_out: 0, imm_out: 0,
        rs1_addr_out: 0, rs2_addr_out: 0, rd_addr_out: 0,
        funct3_out: 0, funct7_out: 0, opcode_out: 0, inst_page_fault_out: 0,
        alu_op_out: 0, alu_src_out: 0,
        reg_write_out: 0, mem_read_out: 0, mem_write_out: 0,
        mem_to_reg_out: 0, branch_out: 0, jump_out: 0, jalr_out: 0
      } do
        # On flush, clear control signals to insert bubble
        pc_out <= mux(flush, lit(0, width: 32), pc_in)
        pc_plus4_out <= mux(flush, lit(4, width: 32), pc_plus4_in)
        rs1_data_out <= mux(flush, lit(0, width: 32), rs1_data_in)
        rs2_data_out <= mux(flush, lit(0, width: 32), rs2_data_in)
        imm_out <= mux(flush, lit(0, width: 32), imm_in)
        rs1_addr_out <= mux(flush, lit(0, width: 5), rs1_addr_in)
        rs2_addr_out <= mux(flush, lit(0, width: 5), rs2_addr_in)
        rd_addr_out <= mux(flush, lit(0, width: 5), rd_addr_in)
        funct3_out <= mux(flush, lit(0, width: 3), funct3_in)
        funct7_out <= mux(flush, lit(0, width: 7), funct7_in)
        opcode_out <= mux(flush, lit(0, width: 7), opcode_in)
        inst_page_fault_out <= mux(flush, lit(0, width: 1), inst_page_fault_in)

        # Control signals - all zero on flush (bubble)
        alu_op_out <= mux(flush, lit(0, width: 5), alu_op_in)
        alu_src_out <= mux(flush, lit(0, width: 1), alu_src_in)
        reg_write_out <= mux(flush, lit(0, width: 1), reg_write_in)
        mem_read_out <= mux(flush, lit(0, width: 1), mem_read_in)
        mem_write_out <= mux(flush, lit(0, width: 1), mem_write_in)
        mem_to_reg_out <= mux(flush, lit(0, width: 1), mem_to_reg_in)
        branch_out <= mux(flush, lit(0, width: 1), branch_in)
        jump_out <= mux(flush, lit(0, width: 1), jump_in)
        jalr_out <= mux(flush, lit(0, width: 1), jalr_in)
      end

        end
      end
    end
  end
end
