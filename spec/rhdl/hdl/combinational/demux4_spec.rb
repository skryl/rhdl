# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::Demux4 do
  let(:demux) { RHDL::HDL::Demux4.new(nil, width: 8) }

  describe 'simulation' do
    it 'routes to correct output' do
      demux.set_input(:a, 0xFF)

      4.times do |sel|
        demux.set_input(:sel, sel)
        demux.propagate

        4.times do |out|
          expected = (out == sel) ? 0xFF : 0
          expect(demux.get_output("y#{out}".to_sym)).to eq(expected)
        end
      end
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Demux4.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Demux4.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # a, sel, y0, y1, y2, y3
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Demux4.to_verilog
      expect(verilog).to include('module demux4')
      expect(verilog).to include('input a')
      expect(verilog).to include('output y0')
    end
  end
end
