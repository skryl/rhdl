# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::PopCount do
  let(:pop) { RHDL::HDL::PopCount.new(nil, width: 8) }

  describe 'simulation' do
    it 'counts set bits' do
      pop.set_input(:a, 0b10101010)
      pop.propagate
      expect(pop.get_output(:count)).to eq(4)

      pop.set_input(:a, 0b11111111)
      pop.propagate
      expect(pop.get_output(:count)).to eq(8)

      pop.set_input(:a, 0b00000000)
      pop.propagate
      expect(pop.get_output(:count)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::PopCount.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::PopCount.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(2)  # a, count
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::PopCount.to_verilog
      expect(verilog).to include('module pop_count')
      expect(verilog).to include('input [7:0] a')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::PopCount.new('popcount', width: 8) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'popcount') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('popcount.a')
      expect(ir.outputs.keys).to include('popcount.count')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module popcount')
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('output [3:0] count')
    end
  end
end
