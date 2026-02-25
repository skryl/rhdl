require_relative '../../spec_helper'
require_relative '../../../../../examples/ao486/hdl/execute/multiply'

RSpec.describe RHDL::Examples::AO486::Multiply do
  let(:mul) { RHDL::Examples::AO486::Multiply.new }

  def multiply(m, src, dst, size: 32, signed: false)
    m.set_input(:src, src)
    m.set_input(:dst, dst)
    m.set_input(:operand_size, size)
    m.set_input(:is_signed, signed ? 1 : 0)
    m.propagate
  end

  describe 'unsigned MUL' do
    it '8-bit: 0x10 * 0x10 = 0x0100' do
      multiply(mul, 0x10, 0x10, size: 8)
      expect(mul.get_output(:result_lo)).to eq(0x00)  # AL
      expect(mul.get_output(:result_hi)).to eq(0x01)  # AH
      expect(mul.get_output(:overflow)).to eq(1)  # AH != 0
    end

    it '16-bit: 0x100 * 0x100 = 0x10000' do
      multiply(mul, 0x100, 0x100, size: 16)
      expect(mul.get_output(:result_lo)).to eq(0)     # AX
      expect(mul.get_output(:result_hi)).to eq(1)     # DX
      expect(mul.get_output(:overflow)).to eq(1)
    end

    it '32-bit: 3 * 7 = 21' do
      multiply(mul, 3, 7, size: 32)
      expect(mul.get_output(:result_lo)).to eq(21)
      expect(mul.get_output(:result_hi)).to eq(0)
      expect(mul.get_output(:overflow)).to eq(0)
    end

    it '32-bit overflow: 0x80000000 * 2' do
      multiply(mul, 0x80000000, 2, size: 32)
      expect(mul.get_output(:result_lo)).to eq(0)
      expect(mul.get_output(:result_hi)).to eq(1)
      expect(mul.get_output(:overflow)).to eq(1)
    end
  end

  describe 'signed IMUL' do
    it '8-bit: -1 * -1 = 1' do
      multiply(mul, 0xFF, 0xFF, size: 8, signed: true)
      # -1 * -1 = 1, fits in 8 bits
      expect(mul.get_output(:result_lo) & 0xFF).to eq(1)
      expect(mul.get_output(:overflow)).to eq(0)
    end

    it '32-bit: -1 * 10 = -10' do
      multiply(mul, 0xFFFFFFFF, 10, size: 32, signed: true)
      expect(mul.get_output(:result_lo)).to eq((-10) & 0xFFFFFFFF)
      expect(mul.get_output(:overflow)).to eq(0)
    end
  end
end
