require 'spec_helper'

RSpec.describe RHDL::HDL::Register do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:reg) { RHDL::HDL::Register.new(nil, width: 8) }

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
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Register.behavior_defined?).to be_truthy
    end

    # Note: Sequential components use rising_edge? which is not yet supported in synthesis context
    it 'generates valid IR', :pending do
      ir = RHDL::HDL::Register.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(5)  # d, clk, rst, en, q
    end

    it 'generates valid Verilog', :pending do
      verilog = RHDL::HDL::Register.to_verilog
      expect(verilog).to include('module register')
      expect(verilog).to include('input [7:0] d')
      expect(verilog).to include('output [7:0] q')
    end
  end
end
