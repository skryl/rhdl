# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::ZeroDetect do
  let(:det) { RHDL::HDL::ZeroDetect.new(nil, width: 8) }

  describe 'simulation' do
    it 'detects zero' do
      det.set_input(:a, 0x00)
      det.propagate

      expect(det.get_output(:zero)).to eq(1)
    end

    it 'detects non-zero' do
      det.set_input(:a, 0x01)
      det.propagate

      expect(det.get_output(:zero)).to eq(0)
    end

    it 'detects non-zero for all bits set' do
      det.set_input(:a, 0xFF)
      det.propagate

      expect(det.get_output(:zero)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::ZeroDetect.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::ZeroDetect.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(2)  # a, zero
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::ZeroDetect.to_verilog
      expect(verilog).to include('module zero_detect')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output zero')
    end
  end
end
