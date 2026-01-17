require 'spec_helper'

RSpec.describe RHDL::HDL::RegisterLoad do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:reg) { RHDL::HDL::RegisterLoad.new }

  before do
    reg.set_input(:rst, 0)
    reg.set_input(:load, 0)
  end

  describe 'simulation' do
    it 'stores 8-bit values when load is high' do
      reg.set_input(:load, 1)
      reg.set_input(:d, 0xAB)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0xAB)
    end

    it 'holds value when load is low' do
      reg.set_input(:load, 1)
      reg.set_input(:d, 0xAB)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0xAB)

      reg.set_input(:load, 0)
      reg.set_input(:d, 0xFF)
      clock_cycle(reg)
      expect(reg.get_output(:q)).to eq(0xAB)  # Still 0xAB
    end

    it 'resets to zero' do
      reg.set_input(:load, 1)
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
      expect(RHDL::HDL::RegisterLoad.behavior_defined? || RHDL::HDL::RegisterLoad.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::RegisterLoad.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(5)  # d, clk, rst, load, q
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::RegisterLoad.to_verilog
      expect(verilog).to include('module register_load')
      expect(verilog).to include('input [7:0] d')
      expect(verilog).to match(/output.*\[7:0\].*q/)
    end
  end
end
