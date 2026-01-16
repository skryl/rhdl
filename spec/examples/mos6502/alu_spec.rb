require_relative 'spec_helper'
require_relative '../../../examples/mos6502/alu'

RSpec.describe MOS6502::ALU do
  let(:alu) { MOS6502::ALU.new }

  before do
    alu.set_input(:c_in, 0)
    alu.set_input(:d_flag, 0)
  end

  describe 'ADC' do
    it 'adds two numbers' do
      alu.set_input(:a, 0x10)
      alu.set_input(:b, 0x20)
      alu.set_input(:op, MOS6502::ALU::OP_ADC)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x30)
      expect(alu.get_output(:z)).to eq(0)
      expect(alu.get_output(:n)).to eq(0)
      expect(alu.get_output(:c)).to eq(0)
    end

    it 'adds with carry in' do
      alu.set_input(:a, 0x10)
      alu.set_input(:b, 0x20)
      alu.set_input(:c_in, 1)
      alu.set_input(:op, MOS6502::ALU::OP_ADC)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x31)
    end

    it 'sets carry on overflow' do
      alu.set_input(:a, 0xFF)
      alu.set_input(:b, 0x01)
      alu.set_input(:op, MOS6502::ALU::OP_ADC)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x00)
      expect(alu.get_output(:c)).to eq(1)
      expect(alu.get_output(:z)).to eq(1)
    end
  end

  describe 'SBC' do
    it 'subtracts two numbers with borrow clear' do
      alu.set_input(:a, 0x30)
      alu.set_input(:b, 0x10)
      alu.set_input(:c_in, 1)  # Carry set means no borrow
      alu.set_input(:op, MOS6502::ALU::OP_SBC)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x20)
      expect(alu.get_output(:c)).to eq(1)
    end
  end

  describe 'Logic operations' do
    it 'performs AND' do
      alu.set_input(:a, 0xF0)
      alu.set_input(:b, 0x0F)
      alu.set_input(:op, MOS6502::ALU::OP_AND)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x00)
      expect(alu.get_output(:z)).to eq(1)
    end

    it 'performs ORA' do
      alu.set_input(:a, 0xF0)
      alu.set_input(:b, 0x0F)
      alu.set_input(:op, MOS6502::ALU::OP_ORA)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0xFF)
      expect(alu.get_output(:n)).to eq(1)
    end
  end

  describe 'Shift operations' do
    it 'performs ASL' do
      alu.set_input(:a, 0x81)
      alu.set_input(:op, MOS6502::ALU::OP_ASL)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x02)
      expect(alu.get_output(:c)).to eq(1)
    end

    it 'performs LSR' do
      alu.set_input(:a, 0x81)
      alu.set_input(:op, MOS6502::ALU::OP_LSR)
      alu.propagate

      expect(alu.get_output(:result)).to eq(0x40)
      expect(alu.get_output(:c)).to eq(1)
    end
  end

  describe 'Compare' do
    it 'compares equal values' do
      alu.set_input(:a, 0x42)
      alu.set_input(:b, 0x42)
      alu.set_input(:op, MOS6502::ALU::OP_CMP)
      alu.propagate

      expect(alu.get_output(:z)).to eq(1)
      expect(alu.get_output(:c)).to eq(1)
    end
  end
end
