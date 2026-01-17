require 'spec_helper'

RSpec.describe RHDL::HDL::AndGate do
  describe 'simulation' do
    it 'performs AND operation' do
      gate = RHDL::HDL::AndGate.new

      gate.set_input(:a0, 0)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)

      gate.set_input(:a0, 1)
      gate.set_input(:a1, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)

      gate.set_input(:a0, 1)
      gate.set_input(:a1, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)
    end

    it 'supports multiple inputs' do
      gate = RHDL::HDL::AndGate.new(nil, inputs: 3)

      gate.set_input(:a0, 1)
      gate.set_input(:a1, 1)
      gate.set_input(:a2, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)

      gate.set_input(:a2, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::AndGate.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::AndGate.to_verilog
      expect(verilog).to include('module and_gate')
      expect(verilog).to include('assign y')
    end
  end
end
