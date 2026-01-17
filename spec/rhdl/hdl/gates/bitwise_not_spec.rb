require 'spec_helper'

RSpec.describe RHDL::HDL::BitwiseNot do
  describe 'simulation' do
    it 'performs 8-bit NOT' do
      gate = RHDL::HDL::BitwiseNot.new(nil, width: 8)
      gate.set_input(:a, 0b11110000)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0b00001111)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::BitwiseNot.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::BitwiseNot.to_verilog
      expect(verilog).to include('assign y')
    end
  end
end
