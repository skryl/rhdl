# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::CPU::CPU do
  describe 'structure' do
    it 'has a structure block defined' do
      expect(RHDL::HDL::CPU::CPU.structure_defined?).to be_truthy
    end

    it 'defines expected ports' do
      cpu = RHDL::HDL::CPU::CPU.new('cpu')

      # Clock and reset
      expect(cpu.inputs.keys).to include(:clk, :rst)

      # Memory interface
      expect(cpu.inputs.keys).to include(:mem_data_in)
      expect(cpu.outputs.keys).to include(:mem_data_out, :mem_addr, :mem_write_en, :mem_read_en)

      # Control inputs
      expect(cpu.inputs.keys).to include(:acc_load_en, :acc_load_data, :pc_load_en, :pc_load_data)
      expect(cpu.inputs.keys).to include(:sp_push, :sp_pop)

      # Status outputs
      expect(cpu.outputs.keys).to include(:pc_out, :acc_out, :sp_out, :halt_out)

      # Decoder outputs
      expect(cpu.outputs.keys).to include(:dec_alu_op, :dec_branch, :dec_jump, :dec_halt)
    end
  end

  describe 'synthesis' do
    it 'generates valid IR' do
      ir = RHDL::HDL::CPU::CPU.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)

      # Check ports exist (port names are symbols)
      port_names = ir.ports.map(&:name)
      expect(port_names).to include(:clk, :rst, :mem_data_in, :mem_addr, :halt_out)
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::CPU::CPU.to_verilog
      expect(verilog).to include('module cpu')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input [7:0] mem_data_in')
      expect(verilog).to include('output [15:0] mem_addr')
      expect(verilog).to include('output halt_out')
    end

    it 'includes submodule instantiations in Verilog' do
      verilog = RHDL::HDL::CPU::CPU.to_verilog
      # Structure components should have instance declarations
      expect(verilog).to include('instruction_decoder') | include('alu') | include('program_counter')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::CPU::CPU.new('cpu') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'cpu') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('cpu.clk', 'cpu.rst', 'cpu.mem_data_in')
      expect(ir.outputs.keys).to include('cpu.mem_addr', 'cpu.halt_out')
    end

    it 'generates gates from subcomponents' do
      # CPU should have gates from ALU, decoder, etc.
      expect(ir.gates.length).to be > 100  # Complex component
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module cpu')
      expect(verilog).to include('input clk')
      expect(verilog).to include('output halt_out')
    end
  end
end
