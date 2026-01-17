# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe MOS6502::Datapath do
  describe 'structure' do
    it 'has structure defined' do
      expect(described_class.structure_defined?).to be_truthy
    end

    it 'defines expected ports' do
      datapath = described_class.new('test_dp')

      # Clock and control
      expect(datapath.inputs.keys).to include(:clk, :rst, :rdy)

      # Memory interface
      expect(datapath.inputs.keys).to include(:data_in)
      expect(datapath.outputs.keys).to include(:data_out, :addr, :rw)

      # Debug outputs
      expect(datapath.outputs.keys).to include(:reg_a, :reg_x, :reg_y, :reg_pc)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module datapath')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('output [15:0] addr')
    end

    it 'includes internal component instances' do
      verilog = described_class.to_verilog
      # Should reference subcomponents or have internal signals
      expect(verilog.length).to be > 1000  # Complex module
    end
  end
end
