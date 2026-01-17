require 'spec_helper'

RSpec.describe RHDL::HDL::TristateBuffer do
  describe 'simulation' do
    it 'passes input to output when enabled' do
      gate = RHDL::HDL::TristateBuffer.new

      gate.set_input(:a, 1)
      gate.set_input(:en, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)

      gate.set_input(:a, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)
    end

    it 'outputs 0 when disabled (synthesizable behavior)' do
      gate = RHDL::HDL::TristateBuffer.new

      gate.set_input(:a, 1)
      gate.set_input(:en, 0)
      gate.propagate
      # Note: For synthesis compatibility, disabled outputs 0 instead of high-Z
      expect(gate.get_output(:y)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::TristateBuffer.behavior_defined?).to be_truthy
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::TristateBuffer.to_verilog
      expect(verilog).to include('assign y')
    end
  end
end
