# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::DecoderN do
  let(:dec) { RHDL::HDL::DecoderN.new(nil, width: 4) }

  describe 'simulation' do
    it 'decodes N-bit input to 2^N outputs' do
      dec.set_input(:en, 1)

      dec.set_input(:a, 10)
      dec.propagate
      expect(dec.get_output(:y10)).to eq(1)
      expect(dec.get_output(:y0)).to eq(0)
      expect(dec.get_output(:y15)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::DecoderN.behavior_defined?).to be_truthy
    end

    # Note: Component uses dynamic output assignment which is not yet supported in synthesis context
    it 'generates valid IR', :pending do
      ir = RHDL::HDL::DecoderN.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
    end

    it 'generates valid Verilog', :pending do
      verilog = RHDL::HDL::DecoderN.to_verilog
      expect(verilog).to include('module decoder_n')
      expect(verilog).to include('input [3:0] a')
    end
  end
end
