require 'spec_helper'

RSpec.describe RHDL::HDL::NotGate do
  let(:gate) { RHDL::HDL::NotGate.new }

  describe 'simulation' do
    it 'inverts the input' do
      gate.set_input(:a, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)

      gate.set_input(:a, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::NotGate.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::NotGate.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(2)
      expect(ir.assigns.length).to be >= 1
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::NotGate.to_verilog
      expect(verilog).to include('module not_gate')
      expect(verilog).to include('input a')
      expect(verilog).to include('output y')
      expect(verilog).to include('assign y')
    end
  end
end
