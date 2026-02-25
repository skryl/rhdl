require_relative '../../spec_helper'
require_relative '../../../../../examples/ao486/hdl/execute/divide'

RSpec.describe RHDL::Examples::AO486::Divide do
  let(:div) { RHDL::Examples::AO486::Divide.new }

  def divide(d, numer, denom, size: 32, signed: false)
    d.set_input(:numer, numer)
    d.set_input(:denom, denom)
    d.set_input(:operand_size, size)
    d.set_input(:is_signed, signed ? 1 : 0)
    d.propagate
  end

  describe 'unsigned DIV' do
    it '32-bit: 100 / 7 = 14 remainder 2' do
      divide(div, 100, 7, size: 32)
      expect(div.get_output(:quotient)).to eq(14)
      expect(div.get_output(:remainder)).to eq(2)
      expect(div.get_output(:exception)).to eq(0)
    end

    it '16-bit: 1000 / 10 = 100 remainder 0' do
      divide(div, 1000, 10, size: 16)
      expect(div.get_output(:quotient)).to eq(100)
      expect(div.get_output(:remainder)).to eq(0)
    end

    it '8-bit: 255 / 16 = 15 remainder 15' do
      divide(div, 255, 16, size: 8)
      expect(div.get_output(:quotient)).to eq(15)
      expect(div.get_output(:remainder)).to eq(15)
    end
  end

  describe 'division by zero' do
    it 'signals exception on divide by zero' do
      divide(div, 100, 0, size: 32)
      expect(div.get_output(:exception)).to eq(1)
    end
  end

  describe 'signed IDIV' do
    it '32-bit: -10 / 3 = -3 remainder -1' do
      divide(div, (-10) & 0xFFFFFFFF_FFFFFFFF, 3, size: 32, signed: true)
      expect(div.get_output(:quotient)).to eq((-3) & 0xFFFFFFFF)
      expect(div.get_output(:remainder)).to eq((-1) & 0xFFFFFFFF)
      expect(div.get_output(:exception)).to eq(0)
    end

    it '32-bit: 10 / -3 = -3 remainder 1' do
      divide(div, 10, (-3) & 0xFFFFFFFF, size: 32, signed: true)
      expect(div.get_output(:quotient)).to eq((-3) & 0xFFFFFFFF)
      expect(div.get_output(:remainder)).to eq(1)
    end
  end

  describe 'overflow detection' do
    it 'signals exception on unsigned overflow' do
      # 0x100 / 1 for 8-bit should overflow (quotient > 255)
      divide(div, 0x100, 1, size: 8)
      expect(div.get_output(:exception)).to eq(1)
    end
  end
end
