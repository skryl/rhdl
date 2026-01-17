# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Mux8 do
  let(:mux) { RHDL::HDL::Mux8.new(nil, width: 8) }

  describe 'simulation' do
    it 'selects from 8 inputs' do
      8.times { |i| mux.set_input("in#{i}".to_sym, (i + 1) * 10) }

      mux.set_input(:sel, 5)
      mux.propagate
      expect(mux.get_output(:y)).to eq(60)

      mux.set_input(:sel, 7)
      mux.propagate
      expect(mux.get_output(:y)).to eq(80)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Mux8.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Mux8.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(10)  # in0-in7, sel, y
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Mux8.to_verilog
      expect(verilog).to include('module mux8')
      expect(verilog).to include('input in0')
      expect(verilog).to include('output y')
    end
  end
end
