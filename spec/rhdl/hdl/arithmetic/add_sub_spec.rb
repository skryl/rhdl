require 'spec_helper'

RSpec.describe RHDL::HDL::AddSub do
  describe 'simulation' do
    it 'performs addition when sub=0' do
      addsub = RHDL::HDL::AddSub.new(nil, width: 8)

      addsub.set_input(:a, 100)
      addsub.set_input(:b, 50)
      addsub.set_input(:sub, 0)
      addsub.propagate
      expect(addsub.get_output(:result)).to eq(150)
    end

    it 'performs subtraction when sub=1' do
      addsub = RHDL::HDL::AddSub.new(nil, width: 8)

      addsub.set_input(:a, 100)
      addsub.set_input(:b, 50)
      addsub.set_input(:sub, 1)
      addsub.propagate
      expect(addsub.get_output(:result)).to eq(50)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::AddSub.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::AddSub.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(8)  # a, b, sub, result, cout, overflow, zero, negative
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::AddSub.to_verilog
      expect(verilog).to include('module add_sub')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [7:0] result')
    end
  end
end
