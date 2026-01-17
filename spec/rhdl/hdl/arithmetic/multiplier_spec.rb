require 'spec_helper'

RSpec.describe RHDL::HDL::Multiplier do
  describe 'simulation' do
    it 'multiplies 8-bit numbers' do
      mult = RHDL::HDL::Multiplier.new(nil, width: 8)

      mult.set_input(:a, 10)
      mult.set_input(:b, 20)
      mult.propagate
      expect(mult.get_output(:product)).to eq(200)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Multiplier.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Multiplier.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(3)  # a, b, product
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Multiplier.to_verilog
      expect(verilog).to include('module multiplier')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [7:0] b')
      expect(verilog).to include('output [15:0] product')
      expect(verilog).to include('assign product')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Multiplier.new('mult', width: 8) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'mult') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('mult.a', 'mult.b')
      expect(ir.outputs.keys).to include('mult.product')
      # Multiplier has many gates for array multiplication
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module mult')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [7:0] b')
      expect(verilog).to include('output [15:0] product')
    end
  end
end
