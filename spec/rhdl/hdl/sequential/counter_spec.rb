require 'spec_helper'

RSpec.describe RHDL::HDL::Counter do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:counter) { RHDL::HDL::Counter.new }

  before do
    counter.set_input(:rst, 0)
    counter.set_input(:en, 1)
    counter.set_input(:up, 1)
    counter.set_input(:load, 0)
  end

  describe 'simulation' do
    it 'counts up' do
      expect(counter.get_output(:q)).to eq(0)

      clock_cycle(counter)
      expect(counter.get_output(:q)).to eq(1)

      clock_cycle(counter)
      expect(counter.get_output(:q)).to eq(2)
    end

    it 'counts down' do
      counter.set_input(:load, 1)
      counter.set_input(:d, 5)
      clock_cycle(counter)
      counter.set_input(:load, 0)

      counter.set_input(:up, 0)
      clock_cycle(counter)
      expect(counter.get_output(:q)).to eq(4)
    end

    it 'wraps around' do
      counter.set_input(:load, 1)
      counter.set_input(:d, 0xFF)
      clock_cycle(counter)
      counter.set_input(:load, 0)

      # At max value (0xFF), tc should be 1
      expect(counter.get_output(:q)).to eq(0xFF)
      expect(counter.get_output(:tc)).to eq(1)

      # After wrap to 0, tc should be 0 (since we're counting up)
      clock_cycle(counter)
      expect(counter.get_output(:q)).to eq(0)
      expect(counter.get_output(:tc)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::Counter.behavior_defined? || RHDL::HDL::Counter.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Counter.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(9)  # clk, rst, en, up, load, d, q, tc, zero
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Counter.to_verilog
      expect(verilog).to include('module counter')
      expect(verilog).to include('input [7:0] d')
      expect(verilog).to match(/output.*\[7:0\].*q/)
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Counter.new('counter') }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'counter') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('counter.clk', 'counter.rst', 'counter.en', 'counter.up', 'counter.load', 'counter.d')
      expect(ir.outputs.keys).to include('counter.q', 'counter.tc', 'counter.zero')
      expect(ir.dffs.length).to eq(8)  # 8-bit counter has 8 DFFs
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module counter')
      expect(verilog).to include('input [7:0] d')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input en')
      expect(verilog).to include('input up')
      expect(verilog).to include('input load')
      expect(verilog).to include('output [7:0] q')
      expect(verilog).to include('output tc')
      expect(verilog).to include('output zero')
    end
  end
end
