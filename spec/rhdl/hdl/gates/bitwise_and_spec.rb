require 'spec_helper'

RSpec.describe RHDL::HDL::BitwiseAnd do
  describe 'simulation' do
    it 'performs 8-bit AND' do
      gate = RHDL::HDL::BitwiseAnd.new(nil, width: 8)
      gate.set_input(:a, 0b11110000)
      gate.set_input(:b, 0b10101010)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0b10100000)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::BitwiseAnd.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog with correct width' do
      verilog = RHDL::HDL::BitwiseAnd.to_verilog
      expect(verilog).to include('[7:0]')  # 8-bit signals
      expect(verilog).to include('assign y')
    end
  end
end
