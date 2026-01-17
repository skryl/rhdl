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

  describe 'gate-level netlist (1-bit)' do
    let(:component) { RHDL::HDL::Demux2.new('demux2', width: 1) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'demux2') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('demux2.a', 'demux2.sel')
      expect(ir.outputs.keys).to include('demux2.y0', 'demux2.y1')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module demux2')
      expect(verilog).to include('input a')
      expect(verilog).to include('input sel')
      expect(verilog).to include('output y0')
      expect(verilog).to include('output y1')
    end
  end
end
