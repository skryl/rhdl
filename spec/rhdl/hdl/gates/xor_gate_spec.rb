require 'spec_helper'

RSpec.describe RHDL::HDL::XorGate do
  describe 'simulation' do
    it 'performs XOR operation' do
      gate = RHDL::HDL::XorGate.new

      gate.set_input(:a0, 0)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)

      gate.set_input(:a0, 1)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)

      gate.set_input(:a0, 1)
      gate.set_input(:a1, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::XorGate.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::XorGate.to_verilog
      expect(verilog).to include('assign y')
    end
  end
end
