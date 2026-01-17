require 'spec_helper'

RSpec.describe RHDL::HDL::Stack do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:stack) { RHDL::HDL::Stack.new }

  before do
    stack.set_input(:rst, 0)
    stack.set_input(:push, 0)
    stack.set_input(:pop, 0)
    stack.propagate  # Initialize outputs
  end

  describe 'simulation' do
    it 'pushes and pops values' do
      # Push 0x11
      stack.set_input(:din, 0x11)
      stack.set_input(:push, 1)
      clock_cycle(stack)

      stack.set_input(:push, 0)
      expect(stack.get_output(:dout)).to eq(0x11)
      expect(stack.get_output(:empty)).to eq(0)

      # Push 0x22
      stack.set_input(:din, 0x22)
      stack.set_input(:push, 1)
      clock_cycle(stack)

      stack.set_input(:push, 0)
      expect(stack.get_output(:dout)).to eq(0x22)

      # Pop - should get 0x22
      stack.set_input(:pop, 1)
      clock_cycle(stack)

      stack.set_input(:pop, 0)
      expect(stack.get_output(:dout)).to eq(0x11)
    end

    it 'indicates empty and full' do
      expect(stack.get_output(:empty)).to eq(1)
      expect(stack.get_output(:full)).to eq(0)

      # Fill the stack (16 entries)
      16.times do |i|
        stack.set_input(:din, i + 1)
        stack.set_input(:push, 1)
        clock_cycle(stack)
        stack.set_input(:push, 0)
      end

      expect(stack.get_output(:empty)).to eq(0)
      expect(stack.get_output(:full)).to eq(1)
    end

    it 'resets correctly' do
      # Push some values
      stack.set_input(:din, 0xFF)
      stack.set_input(:push, 1)
      clock_cycle(stack)

      stack.set_input(:push, 0)
      expect(stack.get_output(:empty)).to eq(0)

      # Reset
      stack.set_input(:rst, 1)
      clock_cycle(stack)

      expect(stack.get_output(:empty)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has memory DSL defined' do
      expect(RHDL::HDL::Stack.memory_dsl_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Stack.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(9)  # clk, rst, push, pop, din, dout, empty, full, sp
      expect(ir.memories.length).to eq(1)
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Stack.to_verilog
      expect(verilog).to include('module stack')
      expect(verilog).to include('input [7:0] din')
      expect(verilog).to match(/output.*\[7:0\].*dout/)
    end
  end
end
