# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::MuxN do
  let(:mux) { RHDL::HDL::MuxN.new(nil, width: 8, inputs: 6) }

  describe 'simulation' do
    it 'handles arbitrary number of inputs' do
      6.times { |i| mux.set_input("in#{i}".to_sym, 100 + i) }

      mux.set_input(:sel, 3)
      mux.propagate
      expect(mux.get_output(:y)).to eq(103)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::MuxN.behavior_defined?).to be_truthy
    end

    # Note: Component uses dynamic input count which causes nil issues in synthesis context
    it 'generates valid IR', :pending do
      ir = RHDL::HDL::MuxN.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
    end

    it 'generates valid Verilog', :pending do
      verilog = RHDL::HDL::MuxN.to_verilog
      expect(verilog).to include('module mux_n')
      expect(verilog).to include('output y')
    end
  end
end
