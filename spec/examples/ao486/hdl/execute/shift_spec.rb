require_relative '../../spec_helper'
require_relative '../../../../../examples/ao486/hdl/execute/shift'

RSpec.describe RHDL::Examples::AO486::Shift do
  let(:sh) { RHDL::Examples::AO486::Shift.new }

  def shift(s, op, value, count, size: 32, cflag_in: 0)
    s.set_input(:shift_op, op)
    s.set_input(:value, value)
    s.set_input(:count, count)
    s.set_input(:operand_size, size)
    s.set_input(:cflag_in, cflag_in)
    s.propagate
  end

  # Shift operations encoded as 3-bit reg field from ModR/M
  SHL = 4
  SHR = 5
  SAR = 7
  ROL = 0
  ROR = 1

  describe 'SHL (logical left shift)' do
    it 'shifts left by 1' do
      shift(sh, SHL, 0x01, 1, size: 8)
      expect(sh.get_output(:result) & 0xFF).to eq(0x02)
      expect(sh.get_output(:cflag)).to eq(0)
    end

    it 'shifts left with carry out' do
      shift(sh, SHL, 0x80, 1, size: 8)
      expect(sh.get_output(:result) & 0xFF).to eq(0x00)
      expect(sh.get_output(:cflag)).to eq(1)
    end

    it 'shifts 32-bit value' do
      shift(sh, SHL, 1, 16, size: 32)
      expect(sh.get_output(:result) & 0xFFFFFFFF).to eq(0x10000)
    end
  end

  describe 'SHR (logical right shift)' do
    it 'shifts right by 1' do
      shift(sh, SHR, 0x02, 1, size: 8)
      expect(sh.get_output(:result) & 0xFF).to eq(0x01)
      expect(sh.get_output(:cflag)).to eq(0)
    end

    it 'shifts right with carry out' do
      shift(sh, SHR, 0x01, 1, size: 8)
      expect(sh.get_output(:result) & 0xFF).to eq(0x00)
      expect(sh.get_output(:cflag)).to eq(1)
    end
  end

  describe 'SAR (arithmetic right shift)' do
    it 'preserves sign bit' do
      shift(sh, SAR, 0x80, 1, size: 8)
      expect(sh.get_output(:result) & 0xFF).to eq(0xC0)  # sign-extended
    end

    it 'shifts positive value same as SHR' do
      shift(sh, SAR, 0x40, 1, size: 8)
      expect(sh.get_output(:result) & 0xFF).to eq(0x20)
    end
  end

  describe 'ROL (rotate left)' do
    it 'rotates MSB into LSB' do
      shift(sh, ROL, 0x80, 1, size: 8)
      expect(sh.get_output(:result) & 0xFF).to eq(0x01)
      expect(sh.get_output(:cflag)).to eq(1)
    end
  end

  describe 'ROR (rotate right)' do
    it 'rotates LSB into MSB' do
      shift(sh, ROR, 0x01, 1, size: 8)
      expect(sh.get_output(:result) & 0xFF).to eq(0x80)
      expect(sh.get_output(:cflag)).to eq(1)
    end
  end

  describe 'zero count' do
    it 'returns input unchanged when count is 0' do
      shift(sh, SHL, 0x42, 0, size: 8)
      expect(sh.get_output(:result) & 0xFF).to eq(0x42)
    end
  end
end
