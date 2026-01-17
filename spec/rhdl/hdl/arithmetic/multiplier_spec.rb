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
end
