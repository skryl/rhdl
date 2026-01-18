# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::CPU::SynthDatapath do
  describe 'structure' do
    it 'has a structure block defined' do
      expect(RHDL::HDL::CPU::SynthDatapath.structure_defined?).to be_truthy
    end

    it 'defines expected ports' do
      datapath = RHDL::HDL::CPU::SynthDatapath.new('dp')

      # Clock and reset
      expect(datapath.inputs.keys).to include(:clk, :rst)

      # Memory interface
      expect(datapath.inputs.keys).to include(:mem_data_in)
      expect(datapath.outputs.keys).to include(:mem_data_out, :mem_addr, :mem_write_en, :mem_read_en)

      # Status outputs
      expect(datapath.outputs.keys).to include(:pc_out, :acc_out, :zero_flag, :halt)
    end
  end

  describe 'synthesis' do
    it 'generates valid IR' do
      ir = RHDL::HDL::CPU::SynthDatapath.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)

      # Check ports exist (port names are symbols)
      port_names = ir.ports.map(&:name)
      expect(port_names).to include(:clk, :rst, :mem_data_in, :mem_addr, :halt)
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::CPU::SynthDatapath.to_verilog
      expect(verilog).to include('module synth_datapath')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input [7:0] mem_data_in')
      expect(verilog).to include('output [15:0] mem_addr')
      expect(verilog).to include('output halt')
    end

    it 'includes submodule instantiations in Verilog' do
      verilog = RHDL::HDL::CPU::SynthDatapath.to_verilog
      # Structural components should have instance declarations
      expect(verilog).to include('instruction_decoder') | include('alu') | include('program_counter')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::CPU::SynthDatapath.new('synth_dp') }
    let(:ir) { RHDL::Export::Structural::Lower.from_components([component], name: 'synth_dp') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('synth_dp.clk', 'synth_dp.rst', 'synth_dp.mem_data_in')
      expect(ir.outputs.keys).to include('synth_dp.mem_addr', 'synth_dp.halt')
    end

    it 'generates gates from subcomponents' do
      # SynthDatapath should have gates from ALU, decoder, etc.
      expect(ir.gates.length).to be > 100  # Complex component
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module synth_dp')
      expect(verilog).to include('input clk')
      expect(verilog).to include('output halt')
    end
  end
end
