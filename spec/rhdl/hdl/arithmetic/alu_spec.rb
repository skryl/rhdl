require 'spec_helper'

RSpec.describe RHDL::HDL::ALU do
  let(:alu) { RHDL::HDL::ALU.new(nil, width: 8) }

  describe 'simulation' do
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

  # Note: ALU uses manual propagate for complex case logic
  # Synthesis tests are omitted since the behavior DSL doesn't support case statements yet
end
