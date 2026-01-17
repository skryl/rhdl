# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Encoder4to2 do
  let(:enc) { RHDL::HDL::Encoder4to2.new }

  describe 'simulation' do
    it 'encodes one-hot input' do
      # Input :a is a 4-bit value where bit 2 is set (0b0100)
      enc.set_input(:a, 0b0100)
      enc.propagate

      expect(enc.get_output(:y)).to eq(2)
      expect(enc.get_output(:valid)).to eq(1)
    end

    it 'indicates invalid when no input' do
      enc.set_input(:a, 0b0000)
      enc.propagate

      expect(enc.get_output(:valid)).to eq(0)
    end

    it 'prioritizes higher input' do
      # Bits 0, 1, and 3 are set - highest is bit 3
      enc.set_input(:a, 0b1011)
      enc.propagate

      expect(enc.get_output(:y)).to eq(3)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Encoder4to2.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Encoder4to2.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(3)  # a, y, valid
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Encoder4to2.to_verilog
      expect(verilog).to include('module encoder4to2')
      expect(verilog).to include('input [3:0] a')
      expect(verilog).to include('output [1:0] y')
    end
  end
end
