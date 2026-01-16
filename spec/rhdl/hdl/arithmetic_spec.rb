require 'spec_helper'

RSpec.describe 'HDL Arithmetic Components' do
  describe RHDL::HDL::HalfAdder do
    it 'adds two bits' do
      adder = RHDL::HDL::HalfAdder.new

      # 0 + 0 = 0
      adder.set_input(:a, 0)
      adder.set_input(:b, 0)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(0)
      expect(adder.get_output(:cout)).to eq(0)

      # 1 + 0 = 1
      adder.set_input(:a, 1)
      adder.set_input(:b, 0)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(1)
      expect(adder.get_output(:cout)).to eq(0)

      # 1 + 1 = 10
      adder.set_input(:a, 1)
      adder.set_input(:b, 1)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(0)
      expect(adder.get_output(:cout)).to eq(1)
    end
  end

  describe RHDL::HDL::FullAdder do
    it 'adds two bits with carry in' do
      adder = RHDL::HDL::FullAdder.new

      # 1 + 1 + 1 = 11
      adder.set_input(:a, 1)
      adder.set_input(:b, 1)
      adder.set_input(:cin, 1)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(1)
      expect(adder.get_output(:cout)).to eq(1)
    end
  end

  describe RHDL::HDL::RippleCarryAdder do
    it 'adds 8-bit numbers' do
      adder = RHDL::HDL::RippleCarryAdder.new(nil, width: 8)

      # 100 + 50 = 150
      adder.set_input(:a, 100)
      adder.set_input(:b, 50)
      adder.set_input(:cin, 0)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(150)
      expect(adder.get_output(:cout)).to eq(0)

      # 200 + 100 = 300 (overflow)
      adder.set_input(:a, 200)
      adder.set_input(:b, 100)
      adder.propagate
      expect(adder.get_output(:sum)).to eq(44)  # 300 & 0xFF
      expect(adder.get_output(:cout)).to eq(1)
    end
  end

  describe RHDL::HDL::ALU do
    let(:alu) { RHDL::HDL::ALU.new(nil, width: 8) }

    it 'performs ADD' do
      alu.set_input(:a, 10)
      alu.set_input(:b, 5)
      alu.set_input(:op, RHDL::HDL::ALU::OP_ADD)
      alu.set_input(:cin, 0)
      alu.propagate

      expect(alu.get_output(:result)).to eq(15)
      expect(alu.get_output(:zero)).to eq(0)
    end

    it 'performs SUB' do
      alu.set_input(:a, 10)
      alu.set_input(:b, 5)
      alu.set_input(:op, RHDL::HDL::ALU::OP_SUB)
      alu.set_input(:cin, 0)
      alu.propagate

      expect(alu.get_output(:result)).to eq(5)
    end

    it 'performs AND' do
      alu.set_input(:a, 0b11110000)
      alu.set_input(:b, 0b10101010)
      alu.set_input(:op, RHDL::HDL::ALU::OP_AND)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0b10100000)
    end

    it 'performs OR' do
      alu.set_input(:a, 0b11110000)
      alu.set_input(:b, 0b00001111)
      alu.set_input(:op, RHDL::HDL::ALU::OP_OR)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0b11111111)
    end

    it 'performs XOR' do
      alu.set_input(:a, 0b11110000)
      alu.set_input(:b, 0b10101010)
      alu.set_input(:op, RHDL::HDL::ALU::OP_XOR)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0b01011010)
    end

    it 'performs NOT' do
      alu.set_input(:a, 0b11110000)
      alu.set_input(:op, RHDL::HDL::ALU::OP_NOT)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0b00001111)
    end

    it 'performs MUL' do
      alu.set_input(:a, 10)
      alu.set_input(:b, 5)
      alu.set_input(:op, RHDL::HDL::ALU::OP_MUL)
      alu.propagate

      expect(alu.get_output(:result)).to eq(50)
    end

    it 'performs DIV' do
      alu.set_input(:a, 20)
      alu.set_input(:b, 4)
      alu.set_input(:op, RHDL::HDL::ALU::OP_DIV)
      alu.propagate

      expect(alu.get_output(:result)).to eq(5)
    end

    it 'sets zero flag' do
      alu.set_input(:a, 5)
      alu.set_input(:b, 5)
      alu.set_input(:op, RHDL::HDL::ALU::OP_SUB)
      alu.set_input(:cin, 0)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0)
      expect(alu.get_output(:zero)).to eq(1)
    end
  end

  describe RHDL::HDL::Comparator do
    let(:cmp) { RHDL::HDL::Comparator.new(nil, width: 8) }

    it 'compares equal values' do
      cmp.set_input(:a, 42)
      cmp.set_input(:b, 42)
      cmp.set_input(:signed, 0)
      cmp.propagate

      expect(cmp.get_output(:eq)).to eq(1)
      expect(cmp.get_output(:gt)).to eq(0)
      expect(cmp.get_output(:lt)).to eq(0)
    end

    it 'compares greater than' do
      cmp.set_input(:a, 50)
      cmp.set_input(:b, 30)
      cmp.set_input(:signed, 0)
      cmp.propagate

      expect(cmp.get_output(:eq)).to eq(0)
      expect(cmp.get_output(:gt)).to eq(1)
      expect(cmp.get_output(:lt)).to eq(0)
    end

    it 'compares less than' do
      cmp.set_input(:a, 20)
      cmp.set_input(:b, 40)
      cmp.set_input(:signed, 0)
      cmp.propagate

      expect(cmp.get_output(:eq)).to eq(0)
      expect(cmp.get_output(:gt)).to eq(0)
      expect(cmp.get_output(:lt)).to eq(1)
    end
  end
end
