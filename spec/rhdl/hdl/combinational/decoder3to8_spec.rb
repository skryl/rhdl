# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Decoder3to8 do
  let(:dec) { RHDL::HDL::Decoder3to8.new }

  describe 'simulation' do
    it 'decodes all 8 values' do
      dec.set_input(:en, 1)

      8.times do |i|
        dec.set_input(:a, i)
        dec.propagate

        8.times do |j|
          expected = (i == j) ? 1 : 0
          expect(dec.get_output("y#{j}".to_sym)).to eq(expected)
        end
      end
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Decoder3to8.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Decoder3to8.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(10)  # a, en, y0-y7
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Decoder3to8.to_verilog
      expect(verilog).to include('module decoder3to8')
      expect(verilog).to include('input [2:0] a')
    end
  end
end
