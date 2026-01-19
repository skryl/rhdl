# RISC-V Verilog Export Tests
# Verifies that all RISC-V components can be exported to Verilog

require 'spec_helper'
require_relative '../../../examples/riscv/hdl/alu'
require_relative '../../../examples/riscv/hdl/decoder'
require_relative '../../../examples/riscv/hdl/imm_gen'
require_relative '../../../examples/riscv/hdl/branch_cond'
require_relative '../../../examples/riscv/hdl/program_counter'
require_relative '../../../examples/riscv/hdl/register_file'
require_relative '../../../examples/riscv/hdl/memory'
require_relative '../../../examples/riscv/hdl/pipeline/if_id_reg'
require_relative '../../../examples/riscv/hdl/pipeline/id_ex_reg'
require_relative '../../../examples/riscv/hdl/pipeline/ex_mem_reg'
require_relative '../../../examples/riscv/hdl/pipeline/mem_wb_reg'
require_relative '../../../examples/riscv/hdl/pipeline/hazard_unit'
require_relative '../../../examples/riscv/hdl/pipeline/forwarding_unit'

RSpec.describe 'RISC-V Verilog Export' do
  describe 'Basic Components' do
    it 'exports ALU to Verilog' do
      verilog = RISCV::ALU.to_verilog
      expect(verilog).to include('module riscv_alu')
      expect(verilog).to include('input [31:0] a')
      expect(verilog).to include('input [31:0] b')
      expect(verilog).to include('output [31:0] result')
      expect(verilog).to include('endmodule')
    end

    it 'exports Decoder to Verilog' do
      verilog = RISCV::Decoder.to_verilog
      expect(verilog).to include('module riscv_decoder')
      expect(verilog).to include('input [31:0] inst')
      expect(verilog).to include('output [4:0] rs1')
      expect(verilog).to include('output [4:0] rs2')
      expect(verilog).to include('output [4:0] rd')
      expect(verilog).to include('endmodule')
    end

    it 'exports ImmGen to Verilog' do
      verilog = RISCV::ImmGen.to_verilog
      expect(verilog).to include('module riscv_imm_gen')
      expect(verilog).to include('input [31:0] inst')
      expect(verilog).to include('output [31:0] imm')
      expect(verilog).to include('endmodule')
    end

    it 'exports BranchCond to Verilog' do
      verilog = RISCV::BranchCond.to_verilog
      expect(verilog).to include('module riscv_branch_cond')
      expect(verilog).to include('output branch_taken')
      expect(verilog).to include('endmodule')
    end

    it 'exports ProgramCounter to Verilog' do
      verilog = RISCV::ProgramCounter.to_verilog
      expect(verilog).to include('module riscv_program_counter')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('output reg [31:0] pc')  # reg for sequential output
      expect(verilog).to include('endmodule')
    end

    it 'exports RegisterFile to Verilog' do
      verilog = RISCV::RegisterFile.to_verilog
      expect(verilog).to include('module riscv_register_file')
      expect(verilog).to include('input [4:0] rs1_addr')
      expect(verilog).to include('input [4:0] rs2_addr')
      expect(verilog).to include('output [31:0] rs1_data')
      expect(verilog).to include('output [31:0] rs2_data')
      expect(verilog).to include('endmodule')
    end

    it 'exports Memory to Verilog' do
      verilog = RISCV::Memory.to_verilog
      expect(verilog).to include('module riscv_memory')
      expect(verilog).to include('input [31:0] addr')
      expect(verilog).to include('output [31:0] read_data')
      expect(verilog).to include('endmodule')
    end
  end

  describe 'Pipeline Registers' do
    it 'exports IF_ID_Reg to Verilog' do
      verilog = RISCV::Pipeline::IF_ID_Reg.to_verilog
      expect(verilog).to include('module riscv_pipeline_if_id_reg')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input stall')
      expect(verilog).to include('input flush')
      expect(verilog).to include('input [31:0] pc_in')
      expect(verilog).to include('input [31:0] inst_in')
      expect(verilog).to include('output reg [31:0] pc_out')  # reg for sequential output
      expect(verilog).to include('output reg [31:0] inst_out')
      expect(verilog).to include('always @(posedge clk)')
      expect(verilog).to include('endmodule')
    end

    it 'exports ID_EX_Reg to Verilog' do
      verilog = RISCV::Pipeline::ID_EX_Reg.to_verilog
      expect(verilog).to include('module riscv_pipeline_id_ex_reg')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input [31:0] rs1_data_in')
      expect(verilog).to include('output reg [31:0] rs1_data_out')  # reg for sequential output
      expect(verilog).to include('endmodule')
    end

    it 'exports EX_MEM_Reg to Verilog' do
      verilog = RISCV::Pipeline::EX_MEM_Reg.to_verilog
      expect(verilog).to include('module riscv_pipeline_ex_mem_reg')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input [31:0] alu_result_in')
      expect(verilog).to include('output reg [31:0] alu_result_out')  # reg for sequential output
      expect(verilog).to include('endmodule')
    end

    it 'exports MEM_WB_Reg to Verilog' do
      verilog = RISCV::Pipeline::MEM_WB_Reg.to_verilog
      expect(verilog).to include('module riscv_pipeline_mem_wb_reg')
      expect(verilog).to include('input clk')
      expect(verilog).to include('output reg [31:0] alu_result_out')  # reg for sequential output
      expect(verilog).to include('output reg [31:0] mem_data_out')
      expect(verilog).to include('endmodule')
    end
  end

  describe 'Control Units' do
    it 'exports HazardUnit to Verilog' do
      verilog = RISCV::Pipeline::HazardUnit.to_verilog
      expect(verilog).to include('module riscv_pipeline_hazard_unit')
      expect(verilog).to include('input [4:0] id_rs1_addr')
      expect(verilog).to include('input [4:0] id_rs2_addr')
      expect(verilog).to include('output stall')
      expect(verilog).to include('output flush_if_id')
      expect(verilog).to include('output flush_id_ex')
      expect(verilog).to include('endmodule')
    end

    it 'exports ForwardingUnit to Verilog' do
      verilog = RISCV::Pipeline::ForwardingUnit.to_verilog
      expect(verilog).to include('module riscv_pipeline_forwarding_unit')
      expect(verilog).to include('input [4:0] ex_rs1_addr')
      expect(verilog).to include('input [4:0] ex_rs2_addr')
      expect(verilog).to include('output [1:0] forward_a')
      expect(verilog).to include('output [1:0] forward_b')
      expect(verilog).to include('endmodule')
    end
  end

  describe 'Verilog Syntax Validity' do
    it 'generates valid module declarations' do
      [
        RISCV::ALU,
        RISCV::Decoder,
        RISCV::ProgramCounter,
        RISCV::Pipeline::IF_ID_Reg,
        RISCV::Pipeline::HazardUnit,
        RISCV::Pipeline::ForwardingUnit
      ].each do |component|
        verilog = component.to_verilog
        expect(verilog).to match(/module\s+\w+/)
        expect(verilog).to match(/endmodule/)

        # Verify balanced parentheses
        open_parens = verilog.count('(')
        close_parens = verilog.count(')')
        expect(open_parens).to eq(close_parens), "Unbalanced parentheses in #{component}"

        # Verify balanced begin/end (some components may have none)
        begin_count = verilog.scan(/\bbegin\b/).length
        # Count 'end' that is not followed by 'module' (to exclude 'endmodule')
        end_count = verilog.scan(/\bend\b(?!module)/).length
        expect(begin_count).to eq(end_count), "Unbalanced begin/end in #{component}: #{begin_count} begins, #{end_count} ends"
      end
    end
  end
end
