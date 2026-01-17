require 'spec_helper'

RSpec.describe RHDL::HDL::Buffer do
  let(:gate) { RHDL::HDL::Buffer.new }

  describe 'simulation' do
    it 'passes input to output' do
      gate.set_input(:a, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)

      gate.set_input(:a, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Buffer.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Buffer.to_verilog
      expect(verilog).to include('assign y')
    end
  end
end
