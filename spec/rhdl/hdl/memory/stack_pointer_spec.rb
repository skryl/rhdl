require 'spec_helper'

RSpec.describe RHDL::HDL::StackPointer do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:sp) { RHDL::HDL::StackPointer.new(nil, width: 8) }

  before do
    sp.set_input(:rst, 0)
    sp.set_input(:push, 0)
    sp.set_input(:pop, 0)
    sp.propagate  # Initialize outputs
  end

  describe 'simulation' do
    it 'initializes to 0xFF' do
      expect(sp.get_output(:q)).to eq(0xFF)
      expect(sp.get_output(:empty)).to eq(1)
    end

    it 'decrements on push' do
      sp.set_input(:push, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFE)
      expect(sp.get_output(:empty)).to eq(0)
    end

    it 'increments on pop' do
      # First push
      sp.set_input(:push, 1)
      clock_cycle(sp)
      sp.set_input(:push, 0)

      # Then pop
      sp.set_input(:pop, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFF)
      expect(sp.get_output(:empty)).to eq(1)
    end

    it 'indicates full when SP reaches 0' do
      # Set SP near bottom
      sp.instance_variable_set(:@state, 1)
      sp.propagate

      sp.set_input(:push, 1)
      clock_cycle(sp)

      expect(sp.get_output(:q)).to eq(0)
      expect(sp.get_output(:full)).to eq(1)
    end

    it 'resets to 0xFF' do
      sp.set_input(:push, 1)
      clock_cycle(sp)
      sp.set_input(:push, 0)

      sp.set_input(:rst, 1)
      clock_cycle(sp)

      expect(sp.get_output(:q)).to eq(0xFF)
      expect(sp.get_output(:empty)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::StackPointer.behavior_defined?).to be_truthy
    end

    # Note: Sequential components use rising_edge? which is not yet supported in synthesis context
    it 'generates valid IR', :pending do
      ir = RHDL::HDL::StackPointer.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(7)  # clk, rst, push, pop, q, empty, full
    end

    it 'generates valid Verilog', :pending do
      verilog = RHDL::HDL::StackPointer.to_verilog
      expect(verilog).to include('module stack_pointer')
      expect(verilog).to include('output [7:0] q')
    end
  end
end
