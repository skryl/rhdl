require 'spec_helper'

RSpec.describe RHDL::HDL::BitwiseOr do
  describe 'simulation' do
    it 'performs 8-bit OR' do
      gate = RHDL::HDL::BitwiseOr.new(nil, width: 8)
      gate.set_input(:a, 0b11110000)
      gate.set_input(:b, 0b00001111)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0b11111111)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::BitwiseOr.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::BitwiseOr.to_verilog
      expect(verilog).to include('assign y')
    end
  end
end
