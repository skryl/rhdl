# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe MOS6502S::AddressLatch do
  let(:latch) { described_class.new('test_addr_latch') }

  describe 'simulation' do
    before do
      latch.set_input(:clk, 0)
      latch.set_input(:rst, 0)
      latch.set_input(:data_in, 0)
      latch.set_input(:load_lo, 0)
      latch.set_input(:load_hi, 0)
      latch.propagate
    end

    it 'loads low byte on load_lo signal' do
      latch.set_input(:data_in, 0x34)
      latch.set_input(:load_lo, 1)
      latch.set_input(:clk, 1)
      latch.propagate

      expect(latch.get_output(:addr) & 0xFF).to eq(0x34)
    end

    it 'loads high byte on load_hi signal' do
      latch.set_input(:data_in, 0x12)
      latch.set_input(:load_hi, 1)
      latch.set_input(:clk, 1)
      latch.propagate

      expect((latch.get_output(:addr) >> 8) & 0xFF).to eq(0x12)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502s_address_latch')
      expect(verilog).to include('addr')
    end
  end
end
