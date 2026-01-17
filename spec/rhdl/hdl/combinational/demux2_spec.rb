# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Demux2 do
  let(:demux) { RHDL::HDL::Demux2.new(nil, width: 8) }

  describe 'simulation' do
    it 'routes to output a when sel=0' do
      demux.set_input(:a, 0x42)
      demux.set_input(:sel, 0)
      demux.propagate

      expect(demux.get_output(:y0)).to eq(0x42)
      expect(demux.get_output(:y1)).to eq(0)
    end

    it 'routes to output b when sel=1' do
      demux.set_input(:a, 0x42)
      demux.set_input(:sel, 1)
      demux.propagate

      expect(demux.get_output(:y0)).to eq(0)
      expect(demux.get_output(:y1)).to eq(0x42)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Demux2.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Demux2.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(4)  # a, sel, y0, y1
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Demux2.to_verilog
      expect(verilog).to include('module demux2')
      expect(verilog).to include('input sel')
    end
  end
end
