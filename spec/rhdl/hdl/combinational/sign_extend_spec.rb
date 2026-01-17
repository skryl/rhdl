# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::SignExtend do
  let(:ext) { RHDL::HDL::SignExtend.new(nil, in_width: 8, out_width: 16) }

  describe 'simulation' do
    it 'extends positive values with zeros' do
      ext.set_input(:a, 0x7F)  # Positive (MSB = 0)
      ext.propagate
      expect(ext.get_output(:y)).to eq(0x007F)
    end

    it 'extends negative values with ones' do
      ext.set_input(:a, 0x80)  # Negative (MSB = 1)
      ext.propagate
      expect(ext.get_output(:y)).to eq(0xFF80)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::SignExtend.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::SignExtend.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(2)  # a, y
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::SignExtend.to_verilog
      expect(verilog).to include('module sign_extend')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [15:0] y')
    end
  end
end
