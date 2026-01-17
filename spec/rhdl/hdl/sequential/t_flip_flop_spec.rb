require 'spec_helper'

RSpec.describe RHDL::HDL::TFlipFlop do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:tff) { RHDL::HDL::TFlipFlop.new }

  before do
    tff.set_input(:rst, 0)
    tff.set_input(:en, 1)
  end

  describe 'simulation' do
    it 'toggles on T=1' do
      tff.set_input(:t, 1)

      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(1)

      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(0)

      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(1)
    end

    it 'holds on T=0' do
      tff.set_input(:t, 1)
      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(1)

      tff.set_input(:t, 0)
      clock_cycle(tff)
      expect(tff.get_output(:q)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::TFlipFlop.behavior_defined? || RHDL::HDL::TFlipFlop.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::TFlipFlop.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # t, clk, rst, en, q, qn
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::TFlipFlop.to_verilog
      expect(verilog).to include('module t_flip_flop')
      expect(verilog).to include('input t')
      expect(verilog).to match(/output.*q/)
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::TFlipFlop.new('tff') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'tff') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('tff.t', 'tff.clk', 'tff.rst', 'tff.en')
      expect(ir.outputs.keys).to include('tff.q', 'tff.qn')
      expect(ir.dffs.length).to eq(1)
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module tff')
      expect(verilog).to include('input t')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input en')
      expect(verilog).to include('output q')
      expect(verilog).to include('output qn')
    end
  end
end
