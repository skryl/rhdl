require 'spec_helper'

RSpec.describe RHDL::HDL::StackPointer do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:sp) { RHDL::HDL::StackPointer.new(nil, width: 8, initial: 0xFF) }

  before do
    sp.set_input(:rst, 0)
    sp.set_input(:push, 0)
    sp.set_input(:pop, 0)
  end

  describe 'simulation' do
    it 'initializes to the specified value' do
      sp.propagate  # Initial propagate to set output wires
      expect(sp.get_output(:q)).to eq(0xFF)
      expect(sp.get_output(:empty)).to eq(1)  # SP at max means empty
      expect(sp.get_output(:full)).to eq(0)
    end

    it 'decrements on push' do
      sp.set_input(:push, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFE)
      expect(sp.get_output(:empty)).to eq(0)
    end

    it 'increments on pop' do
      # First push to decrement
      sp.set_input(:push, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFE)

      # Now pop to increment
      sp.set_input(:push, 0)
      sp.set_input(:pop, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFF)
      expect(sp.get_output(:empty)).to eq(1)
    end

    it 'indicates full when SP is 0' do
      # Start with SP at a low value
      sp_low = RHDL::HDL::StackPointer.new(nil, width: 8, initial: 0x01)
      sp_low.set_input(:rst, 0)
      sp_low.set_input(:push, 1)
      sp_low.set_input(:pop, 0)
      clock_cycle(sp_low)
      expect(sp_low.get_output(:q)).to eq(0x00)
      expect(sp_low.get_output(:full)).to eq(1)
    end

    it 'wraps around on underflow' do
      sp_at_zero = RHDL::HDL::StackPointer.new(nil, width: 8, initial: 0x00)
      sp_at_zero.set_input(:rst, 0)
      sp_at_zero.set_input(:push, 1)
      sp_at_zero.set_input(:pop, 0)
      clock_cycle(sp_at_zero)
      expect(sp_at_zero.get_output(:q)).to eq(0xFF)  # Wrapped around
    end

    it 'resets to initial value' do
      sp.set_input(:push, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFE)

      sp.set_input(:push, 0)
      sp.set_input(:rst, 1)
      clock_cycle(sp)
      expect(sp.get_output(:q)).to eq(0xFF)
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::StackPointer.behavior_defined? || RHDL::HDL::StackPointer.sequential_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::StackPointer.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(7)  # clk, rst, push, pop, q, empty, full
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::StackPointer.to_verilog
      expect(verilog).to include('module stack_pointer')
      expect(verilog).to match(/output.*\[7:0\].*q/)
    end
  end
end
