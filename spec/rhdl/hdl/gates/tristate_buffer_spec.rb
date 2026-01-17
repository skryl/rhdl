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

    it 'outputs high-Z when disabled' do
      gate = RHDL::HDL::TristateBuffer.new

      gate.set_input(:a, 1)
      gate.set_input(:en, 0)
      gate.propagate
      # Access the wire's raw signal value since get_output returns to_i (0 for Z)
      output_wire = gate.instance_variable_get(:@outputs)[:y]
      expect(output_wire.instance_variable_get(:@value).value).to eq(RHDL::HDL::SignalValue::Z)
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
