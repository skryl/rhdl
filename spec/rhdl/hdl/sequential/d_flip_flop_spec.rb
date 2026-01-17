require 'spec_helper'

RSpec.describe RHDL::HDL::DFlipFlop do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:dff) { RHDL::HDL::DFlipFlop.new }

  before do
    dff.set_input(:rst, 0)
    dff.set_input(:en, 1)
  end

  describe 'simulation' do
    it 'captures input on rising edge' do
      dff.set_input(:d, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)
      expect(dff.get_output(:qn)).to eq(0)
    end

    it 'holds value when enable is low' do
      dff.set_input(:d, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)

      dff.set_input(:en, 0)
      dff.set_input(:d, 0)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)  # Still 1
    end

    it 'resets on reset signal' do
      dff.set_input(:d, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(1)

      dff.set_input(:rst, 1)
      clock_cycle(dff)
      expect(dff.get_output(:q)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::DFlipFlop.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::DFlipFlop.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # d, clk, rst, en, q, qn
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::DFlipFlop.to_verilog
      expect(verilog).to include('module d_flip_flop')
      expect(verilog).to include('input d')
      expect(verilog).to include('output q')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::DFlipFlop.new('dff') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'dff') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('dff.d', 'dff.clk', 'dff.rst', 'dff.en')
      expect(ir.outputs.keys).to include('dff.q', 'dff.qn')
      expect(ir.dffs.length).to eq(1)
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module dff')
      expect(verilog).to include('input d')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input en')
      expect(verilog).to include('output q')
      expect(verilog).to include('output qn')
    end
  end
end
