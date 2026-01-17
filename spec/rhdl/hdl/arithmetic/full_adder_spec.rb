require 'spec_helper'

RSpec.describe RHDL::HDL::FullAdder do
  describe 'simulation' do
    it 'adds two bits with carry in' do
      adder = RHDL::HDL::FullAdder.new

      # 1 + 1 + 1 = 11
      adder.set_input(:a, 1)
      adder.set_input(:b, 1)
      adder.set_input(:cin, 1)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(1)
      expect(adder.get_output(:cout)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::FullAdder.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::FullAdder.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(5)  # a, b, cin, sum, cout
      expect(ir.assigns.length).to be >= 2
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::FullAdder.to_verilog
      expect(verilog).to include('module full_adder')
      expect(verilog).to include('input a')
      expect(verilog).to include('input b')
      expect(verilog).to include('input cin')
      expect(verilog).to include('output sum')
      expect(verilog).to include('output cout')
      expect(verilog).to include('assign sum')
      expect(verilog).to include('assign cout')
    end
  end
end
