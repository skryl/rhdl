require_relative '../../spec_helper'
require_relative '../../../../../examples/ao486/hdl/execute/alu'

RSpec.describe RHDL::Examples::AO486::ALU do
  C = RHDL::Examples::AO486::Constants unless defined?(C)
  let(:alu) { RHDL::Examples::AO486::ALU.new }

  def compute(a, op, src, dst, size: 32, cflag_in: 0)
    a.set_input(:arith_index, op)
    a.set_input(:src, src)
    a.set_input(:dst, dst)
    a.set_input(:operand_size, size)
    a.set_input(:cflag_in, cflag_in)
    a.propagate
  end

  describe 'ADD' do
    it 'computes 0x10 + 0x20 = 0x30 with flags cleared' do
      compute(alu, C::ARITH_ADD, 0x20, 0x10, size: 32)
      expect(alu.get_output(:result)).to eq(0x30)
      expect(alu.get_output(:zflag)).to eq(0)
      expect(alu.get_output(:cflag)).to eq(0)
      expect(alu.get_output(:sflag)).to eq(0)
      expect(alu.get_output(:oflag)).to eq(0)
    end

    it 'sets ZF when result is 0' do
      compute(alu, C::ARITH_ADD, 0, 0, size: 32)
      expect(alu.get_output(:result)).to eq(0)
      expect(alu.get_output(:zflag)).to eq(1)
    end

    it 'sets CF on 8-bit overflow' do
      compute(alu, C::ARITH_ADD, 0x80, 0x80, size: 8)
      expect(alu.get_output(:result) & 0xFF).to eq(0)
      expect(alu.get_output(:cflag)).to eq(1)
      expect(alu.get_output(:zflag)).to eq(1)
    end

    it 'sets SF when result is negative (MSB set)' do
      compute(alu, C::ARITH_ADD, 0x7F, 0x01, size: 8)
      expect(alu.get_output(:result) & 0xFF).to eq(0x80)
      expect(alu.get_output(:sflag)).to eq(1)
    end

    it 'sets OF on signed overflow (positive + positive = negative)' do
      compute(alu, C::ARITH_ADD, 0x7FFFFFFF, 1, size: 32)
      expect(alu.get_output(:result) & 0xFFFFFFFF).to eq(0x80000000)
      expect(alu.get_output(:oflag)).to eq(1)
      expect(alu.get_output(:sflag)).to eq(1)
    end

    it 'sets CF on 16-bit overflow' do
      compute(alu, C::ARITH_ADD, 0xFFFF, 1, size: 16)
      expect(alu.get_output(:result) & 0xFFFF).to eq(0)
      expect(alu.get_output(:cflag)).to eq(1)
    end
  end

  describe 'SUB' do
    it 'computes 0x30 - 0x10 = 0x20' do
      compute(alu, C::ARITH_SUB, 0x10, 0x30, size: 32)
      expect(alu.get_output(:result) & 0xFFFFFFFF).to eq(0x20)
      expect(alu.get_output(:cflag)).to eq(0)
    end

    it 'sets CF on unsigned borrow' do
      compute(alu, C::ARITH_SUB, 0x20, 0x10, size: 32)
      expect(alu.get_output(:cflag)).to eq(1)
    end

    it 'sets ZF when result is 0' do
      compute(alu, C::ARITH_SUB, 0x42, 0x42, size: 32)
      expect(alu.get_output(:result) & 0xFFFFFFFF).to eq(0)
      expect(alu.get_output(:zflag)).to eq(1)
    end

    it 'sets OF on signed overflow (neg - pos = pos)' do
      compute(alu, C::ARITH_SUB, 1, 0x80000000, size: 32)
      expect(alu.get_output(:result) & 0xFFFFFFFF).to eq(0x7FFFFFFF)
      expect(alu.get_output(:oflag)).to eq(1)
    end
  end

  describe 'AND' do
    it 'computes 0xFF00 AND 0x0F0F = 0x0F00' do
      compute(alu, C::ARITH_AND, 0x0F0F, 0xFF00, size: 16)
      expect(alu.get_output(:result) & 0xFFFF).to eq(0x0F00)
      expect(alu.get_output(:cflag)).to eq(0)
      expect(alu.get_output(:oflag)).to eq(0)
    end
  end

  describe 'OR' do
    it 'computes 0xF000 OR 0x000F = 0xF00F' do
      compute(alu, C::ARITH_OR, 0x000F, 0xF000, size: 16)
      expect(alu.get_output(:result) & 0xFFFF).to eq(0xF00F)
    end
  end

  describe 'XOR' do
    it 'computes 0xFF XOR 0xFF = 0' do
      compute(alu, C::ARITH_XOR, 0xFF, 0xFF, size: 8)
      expect(alu.get_output(:result) & 0xFF).to eq(0)
      expect(alu.get_output(:zflag)).to eq(1)
    end
  end

  describe 'ADC' do
    it 'adds with carry flag' do
      compute(alu, C::ARITH_ADC, 0x10, 0x20, size: 32, cflag_in: 1)
      expect(alu.get_output(:result) & 0xFFFFFFFF).to eq(0x31)
    end
  end

  describe 'SBB' do
    it 'subtracts with borrow' do
      compute(alu, C::ARITH_SBB, 0x10, 0x30, size: 32, cflag_in: 1)
      expect(alu.get_output(:result) & 0xFFFFFFFF).to eq(0x1F)
    end
  end

  describe 'CMP (same as SUB)' do
    it 'sets flags like SUB' do
      compute(alu, C::ARITH_CMP, 0x42, 0x42, size: 32)
      expect(alu.get_output(:zflag)).to eq(1)
    end
  end

  describe 'parity flag' do
    it 'sets PF when low byte has even number of bits' do
      compute(alu, C::ARITH_ADD, 0, 0, size: 8)  # result=0, PF=1 (even parity)
      expect(alu.get_output(:pflag)).to eq(1)
    end

    it 'clears PF when low byte has odd number of bits' do
      compute(alu, C::ARITH_ADD, 1, 0, size: 8)  # result=1, PF=0 (odd parity)
      expect(alu.get_output(:pflag)).to eq(0)
    end
  end
end
