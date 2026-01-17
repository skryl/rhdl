# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Decoder2to4 do
  let(:dec) { RHDL::HDL::Decoder2to4.new }

  describe 'simulation' do
    it 'produces one-hot output' do
      dec.set_input(:en, 1)

      dec.set_input(:a, 0)
      dec.propagate
      expect(dec.get_output(:y0)).to eq(1)
      expect(dec.get_output(:y1)).to eq(0)
      expect(dec.get_output(:y2)).to eq(0)
      expect(dec.get_output(:y3)).to eq(0)

      dec.set_input(:a, 2)
      dec.propagate
      expect(dec.get_output(:y0)).to eq(0)
      expect(dec.get_output(:y2)).to eq(1)
    end

    it 'outputs all zeros when disabled' do
      dec.set_input(:en, 0)
      dec.set_input(:a, 1)
      dec.propagate

      expect(dec.get_output(:y0)).to eq(0)
      expect(dec.get_output(:y1)).to eq(0)
      expect(dec.get_output(:y2)).to eq(0)
      expect(dec.get_output(:y3)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Decoder2to4.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Decoder2to4.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # a, en, y0, y1, y2, y3
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Decoder2to4.to_verilog
      expect(verilog).to include('module decoder2to4')
      expect(verilog).to include('input [1:0] a')
    end
  end
end
