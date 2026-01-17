# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Mux2 do
  let(:mux) { RHDL::HDL::Mux2.new(nil, width: 8) }

  describe 'simulation' do
    it 'selects input a when sel=0' do
      mux.set_input(:a, 0x11)
      mux.set_input(:b, 0x22)
      mux.set_input(:sel, 0)
      mux.propagate

      expect(mux.get_output(:y)).to eq(0x11)
    end

    it 'selects input b when sel=1' do
      mux.set_input(:a, 0x11)
      mux.set_input(:b, 0x22)
      mux.set_input(:sel, 1)
      mux.propagate

      expect(mux.get_output(:y)).to eq(0x22)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Mux2.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Mux2.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(4)  # a, b, sel, y
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Mux2.to_verilog
      expect(verilog).to include('module mux2')
      expect(verilog).to include('assign y')
    end
  end
end
