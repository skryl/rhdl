# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::ZeroExtend do
  let(:ext) { RHDL::HDL::ZeroExtend.new(nil, in_width: 8, out_width: 16) }

  describe 'simulation' do
    it 'extends with zeros' do
      ext.set_input(:a, 0xFF)
      ext.propagate
      expect(ext.get_output(:y)).to eq(0x00FF)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::ZeroExtend.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::ZeroExtend.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::ZeroExtend.to_verilog
      expect(verilog).to include('module zero_extend')
      expect(verilog).to include('assign y')
    end
  end
end
