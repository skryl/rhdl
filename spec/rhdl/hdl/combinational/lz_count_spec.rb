# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::LZCount do
  let(:lzc) { RHDL::HDL::LZCount.new(nil, width: 8) }

  describe 'simulation' do
    it 'counts leading zeros' do
      lzc.set_input(:a, 0b10000000)
      lzc.propagate
      expect(lzc.get_output(:count)).to eq(0)

      lzc.set_input(:a, 0b00001000)
      lzc.propagate
      expect(lzc.get_output(:count)).to eq(4)

      lzc.set_input(:a, 0b00000001)
      lzc.propagate
      expect(lzc.get_output(:count)).to eq(7)

      lzc.set_input(:a, 0b00000000)
      lzc.propagate
      expect(lzc.get_output(:count)).to eq(8)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::LZCount.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::LZCount.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(3)  # a, count, zero
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::LZCount.to_verilog
      expect(verilog).to include('module lz_count')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [3:0] count')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::LZCount.new('lzcount', width: 8) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'lzcount') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('lzcount.a')
      expect(ir.outputs.keys).to include('lzcount.count', 'lzcount.all_zero')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module lzcount')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [3:0] count')
      expect(verilog).to include('output all_zero')
    end
  end
end
