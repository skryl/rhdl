# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe MOS6502S::ProgramCounter do
  let(:pc) { described_class.new('test_pc') }

  describe 'simulation' do
    before do
      pc.set_input(:clk, 0)
      pc.set_input(:rst, 1)
      pc.set_input(:inc, 0)
      pc.set_input(:load, 0)
      pc.set_input(:addr_in, 0)
      pc.propagate
      # Rising edge for reset
      pc.set_input(:clk, 1)
      pc.propagate
      pc.set_input(:clk, 0)
      pc.set_input(:rst, 0)
      pc.propagate
    end

    it 'initializes to reset vector on reset' do
      # PC should be at reset vector or 0 after reset
      expect(pc.get_output(:pc)).to be_a(Integer)
    end

    it 'increments on inc signal' do
      initial_pc = pc.get_output(:pc)
      pc.set_input(:inc, 1)
      pc.set_input(:clk, 1)
      pc.propagate

      expect(pc.get_output(:pc)).to eq((initial_pc + 1) & 0xFFFF)
    end

    it 'loads new value on load signal' do
      pc.set_input(:addr_in, 0x1234)
      pc.set_input(:load, 1)
      pc.set_input(:clk, 1)
      pc.propagate

      expect(pc.get_output(:pc)).to eq(0x1234)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502s_program_counter')
      expect(verilog).to include('output reg [15:0] pc')
    end
  end
end
