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
    it 'has a behavior block defined' do
      expect(RHDL::HDL::TFlipFlop.behavior_defined?).to be_truthy
    end

    # Note: Sequential components use rising_edge? which is not yet supported in synthesis context
    it 'generates valid IR', :pending do
      ir = RHDL::HDL::TFlipFlop.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(6)  # t, clk, rst, en, q, qn
    end

    it 'generates valid Verilog', :pending do
      verilog = RHDL::HDL::TFlipFlop.to_verilog
      expect(verilog).to include('module t_flip_flop')
      expect(verilog).to include('input t')
      expect(verilog).to include('output q')
    end
  end
end
