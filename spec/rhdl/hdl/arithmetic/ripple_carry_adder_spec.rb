require 'spec_helper'

RSpec.describe RHDL::HDL::RippleCarryAdder do
  describe 'simulation' do
    it 'adds 8-bit numbers' do
      adder = RHDL::HDL::RippleCarryAdder.new(nil, width: 8)

      # 100 + 50 = 150
      adder.set_input(:a, 100)
      adder.set_input(:b, 50)
      adder.set_input(:cin, 0)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(150)
      expect(adder.get_output(:cout)).to eq(0)

      # 200 + 100 = 300 (overflow)
      adder.set_input(:a, 200)
      adder.set_input(:b, 100)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(44)  # 300 & 0xFF
      expect(adder.get_output(:cout)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::RippleCarryAdder.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::RippleCarryAdder.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # a, b, cin, sum, cout, overflow
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::RippleCarryAdder.to_verilog
      expect(verilog).to include('module ripple_carry_adder')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [7:0] b')
      expect(verilog).to include('output [7:0] sum')
      expect(verilog).to include('assign sum')
    end
  end
end
