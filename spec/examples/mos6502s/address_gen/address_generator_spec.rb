# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe MOS6502S::AddressGenerator do
  let(:ag) { described_class.new('test_ag') }

  describe 'simulation' do
    before do
      ag.set_input(:mode, 0)
      ag.set_input(:operand_lo, 0)
      ag.set_input(:operand_hi, 0)
      ag.set_input(:x_reg, 0)
      ag.set_input(:y_reg, 0)
      ag.set_input(:pc, 0)
      ag.set_input(:sp, 0xFF)
      ag.set_input(:indirect_lo, 0)
      ag.set_input(:indirect_hi, 0)
      ag.propagate
    end

    it 'computes zero page address' do
      ag.set_input(:mode, MOS6502S::AddressGenerator::MODE_ZERO_PAGE)
      ag.set_input(:operand_lo, 0x80)
      ag.propagate

      expect(ag.get_output(:eff_addr)).to eq(0x0080)
      expect(ag.get_output(:is_zero_page)).to eq(1)
    end

    it 'computes absolute address' do
      ag.set_input(:mode, MOS6502S::AddressGenerator::MODE_ABSOLUTE)
      ag.set_input(:operand_lo, 0x34)
      ag.set_input(:operand_hi, 0x12)
      ag.propagate

      expect(ag.get_output(:eff_addr)).to eq(0x1234)
    end

    it 'computes zero page X indexed address' do
      ag.set_input(:mode, MOS6502S::AddressGenerator::MODE_ZERO_PAGE_X)
      ag.set_input(:operand_lo, 0x80)
      ag.set_input(:x_reg, 0x10)
      ag.propagate

      expect(ag.get_output(:eff_addr)).to eq(0x0090)
      expect(ag.get_output(:is_zero_page)).to eq(1)
    end

    it 'computes absolute X indexed address' do
      ag.set_input(:mode, MOS6502S::AddressGenerator::MODE_ABSOLUTE_X)
      ag.set_input(:operand_lo, 0x00)
      ag.set_input(:operand_hi, 0x10)
      ag.set_input(:x_reg, 0x20)
      ag.propagate

      expect(ag.get_output(:eff_addr)).to eq(0x1020)
    end

    it 'computes stack address' do
      ag.set_input(:mode, MOS6502S::AddressGenerator::MODE_STACK)
      ag.set_input(:sp, 0xFD)
      ag.propagate

      expect(ag.get_output(:eff_addr)).to eq(0x01FD)
    end
  end

  describe 'synthesis' do
    it 'generates valid Verilog' do
      verilog = described_class.to_verilog
      expect(verilog).to include('module mos6502s_address_generator')
      expect(verilog).to include('input [3:0] mode')
      expect(verilog).to include('output')
      expect(verilog).to include('eff_addr')
    end
  end
end
