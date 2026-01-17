require 'spec_helper'

RSpec.describe RHDL::HDL::NorGate do
  describe 'simulation' do
    it 'performs NOR operation' do
      gate = RHDL::HDL::NorGate.new

      gate.set_input(:a0, 0)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)

      gate.set_input(:a0, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::NorGate.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::NorGate.to_verilog
      expect(verilog).to include('assign y')
    end
  end
end
