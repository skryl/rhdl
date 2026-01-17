require 'spec_helper'

RSpec.describe RHDL::HDL::Register do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:reg) { RHDL::HDL::Register.new }

  before do
    reg.set_input(:rst, 0)
    reg.set_input(:en, 1)
  end

  describe 'simulation' do
    it 'stores 8-bit values' do
      reg.set_input(:d, 0xAB)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0xAB)
    end

    it 'resets to zero' do
      reg.set_input(:d, 0xFF)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0xFF)

      reg.set_input(:rst, 1)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::Register.behavior_defined? || RHDL::HDL::Register.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Register.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(5)  # d, clk, rst, en, q
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Register.to_verilog
      expect(verilog).to include('module register')
      expect(verilog).to include('input [7:0] d')
      expect(verilog).to match(/output.*\[7:0\].*q/)
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Register.new('reg8') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'reg8') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('reg8.d', 'reg8.clk', 'reg8.rst', 'reg8.en')
      expect(ir.outputs.keys).to include('reg8.q')
      expect(ir.dffs.length).to eq(8)  # 8-bit register has 8 DFFs
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module reg8')
      expect(verilog).to include('input [7:0] d')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input en')
      expect(verilog).to include('output [7:0] q')
    end
  end
end
