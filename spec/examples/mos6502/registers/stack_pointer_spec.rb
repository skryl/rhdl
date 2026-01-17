# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe MOS6502::StackPointer do
  let(:sp) { described_class.new('test_sp') }

  describe 'simulation' do
    before do
      sp.set_input(:clk, 0)
      sp.set_input(:rst, 1)
      sp.set_input(:inc, 0)
      sp.set_input(:dec, 0)
      sp.set_input(:load, 0)
      sp.set_input(:data_in, 0)
      sp.propagate
      # Rising edge for reset
      sp.set_input(:clk, 1)
      sp.propagate
      sp.set_input(:clk, 0)
      sp.set_input(:rst, 0)
      sp.propagate
    end

    it 'initializes to 0xFD after reset' do
      # 6502 SP is initialized to 0xFD after reset sequence
      expect(sp.get_output(:sp)).to eq(0xFD)
    end

    it 'decrements on push' do
      initial_sp = sp.get_output(:sp)
      sp.set_input(:dec, 1)
      sp.set_input(:clk, 1)
      sp.propagate

      expect(sp.get_output(:sp)).to eq(initial_sp - 1)
    end

    it 'increments on pull' do
      initial_sp = sp.get_output(:sp)

      # First decrement
      sp.set_input(:dec, 1)
      sp.set_input(:clk, 1)
      sp.propagate
      sp.set_input(:clk, 0)
      sp.set_input(:dec, 0)
      sp.propagate

      # Then increment
      sp.set_input(:inc, 1)
      sp.set_input(:clk, 1)
      sp.propagate

      expect(sp.get_output(:sp)).to eq(initial_sp)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502_stack_pointer')
      expect(verilog).to include('output')
      expect(verilog).to include('sp')
    end
  end
end
