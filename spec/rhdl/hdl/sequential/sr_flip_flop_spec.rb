require 'spec_helper'

RSpec.describe RHDL::HDL::SRFlipFlop do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:srff) { RHDL::HDL::SRFlipFlop.new }

  before do
    srff.set_input(:rst, 0)
    srff.set_input(:en, 1)
  end

  describe 'simulation' do
    it 'holds state when S=0 and R=0' do
      srff.set_input(:s, 1)
      srff.set_input(:r, 0)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(1)

      srff.set_input(:s, 0)
      srff.set_input(:r, 0)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(1)  # Hold
    end

    it 'resets when S=0 and R=1' do
      srff.set_input(:s, 1)
      srff.set_input(:r, 0)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(1)

      srff.set_input(:s, 0)
      srff.set_input(:r, 1)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(0)
      expect(srff.get_output(:qn)).to eq(1)
    end

    it 'sets when S=1 and R=0' do
      srff.set_input(:s, 1)
      srff.set_input(:r, 0)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(1)
      expect(srff.get_output(:qn)).to eq(0)
    end

    it 'handles invalid state S=1 R=1 by defaulting to 0' do
      srff.set_input(:s, 1)
      srff.set_input(:r, 0)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(1)

      srff.set_input(:s, 1)
      srff.set_input(:r, 1)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(0)  # Invalid defaults to 0
    end

    it 'resets on reset signal' do
      srff.set_input(:s, 1)
      srff.set_input(:r, 0)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(1)

      srff.set_input(:rst, 1)
      clock_cycle(srff)
      expect(srff.get_output(:q)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::SRFlipFlop.behavior_defined? || RHDL::HDL::SRFlipFlop.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::SRFlipFlop.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(7)  # s, r, clk, rst, en, q, qn
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::SRFlipFlop.to_verilog
      expect(verilog).to include('module sr_flip_flop')
      expect(verilog).to include('input s')
      expect(verilog).to include('input r')
      expect(verilog).to match(/output.*q/)
    end
  end
end
