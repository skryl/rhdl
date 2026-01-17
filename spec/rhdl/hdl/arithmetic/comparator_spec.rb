require 'spec_helper'

RSpec.describe RHDL::HDL::Comparator do
  let(:cmp) { RHDL::HDL::Comparator.new(nil, width: 8) }

  describe 'simulation' do
    it 'compares equal values' do
      cmp.set_input(:a, 42)
      cmp.set_input(:b, 42)
      cmp.set_input(:signed_cmp, 0)
      cmp.propagate

      expect(cmp.get_output(:eq)).to eq(1)
      expect(cmp.get_output(:gt)).to eq(0)
      expect(cmp.get_output(:lt)).to eq(0)
    end

    it 'compares greater than' do
      cmp.set_input(:a, 50)
      cmp.set_input(:b, 30)
      cmp.set_input(:signed_cmp, 0)
      cmp.propagate

      expect(cmp.get_output(:eq)).to eq(0)
      expect(cmp.get_output(:gt)).to eq(1)
      expect(cmp.get_output(:lt)).to eq(0)
    end

    it 'compares less than' do
      cmp.set_input(:a, 20)
      cmp.set_input(:b, 40)
      cmp.set_input(:signed_cmp, 0)
      cmp.propagate

      expect(cmp.get_output(:eq)).to eq(0)
      expect(cmp.get_output(:gt)).to eq(0)
      expect(cmp.get_output(:lt)).to eq(1)
    end

    it 'handles signed comparison with negative numbers' do
      # -1 (0xFF) vs 1 - signed comparison should show -1 < 1
      cmp.set_input(:a, 0xFF)  # -1 in signed
      cmp.set_input(:b, 1)
      cmp.set_input(:signed_cmp, 1)
      cmp.propagate

      expect(cmp.get_output(:lt)).to eq(1)
      expect(cmp.get_output(:gt)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Comparator.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Comparator.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(8)  # a, b, signed_cmp, eq, gt, lt, gte, lte
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Comparator.to_verilog
      expect(verilog).to include('module comparator')
      expect(verilog).to include('input [7:0] a')
    end
  end
end
