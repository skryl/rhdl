require 'spec_helper'

RSpec.describe RHDL::HDL::HalfAdder do
  describe 'simulation' do
    it 'adds two bits' do
      adder = RHDL::HDL::HalfAdder.new

      # 0 + 0 = 0
      adder.set_input(:a, 0)
      adder.set_input(:b, 0)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(0)
      expect(adder.get_output(:cout)).to eq(0)

      # 1 + 0 = 1
      adder.set_input(:a, 1)
      adder.set_input(:b, 0)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(1)
      expect(adder.get_output(:cout)).to eq(0)

      # 1 + 1 = 10
      adder.set_input(:a, 1)
      adder.set_input(:b, 1)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(0)
      expect(adder.get_output(:cout)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::HalfAdder.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::HalfAdder.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(4)  # a, b, sum, cout
      expect(ir.assigns.length).to be >= 2
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::HalfAdder.to_verilog
      expect(verilog).to include('module half_adder')
      expect(verilog).to include('input a')
      expect(verilog).to include('input b')
      expect(verilog).to include('output sum')
      expect(verilog).to include('output cout')
      expect(verilog).to include('assign sum')
      expect(verilog).to include('assign cout')
    end
  end
end
