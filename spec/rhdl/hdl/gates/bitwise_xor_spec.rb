require 'spec_helper'

RSpec.describe RHDL::HDL::BitwiseXor do
  describe 'simulation' do
    it 'performs 8-bit XOR' do
      gate = RHDL::HDL::BitwiseXor.new(nil, width: 8)
      gate.set_input(:a, 0b11110000)
      gate.set_input(:b, 0b10101010)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0b01011010)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::BitwiseXor.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::BitwiseXor.to_verilog
      expect(verilog).to include('assign y')
    end
  end
end
