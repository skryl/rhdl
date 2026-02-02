# frozen_string_literal: true

require 'spec_helper'

# SM83 ALU Tests
# Tests the Game Boy CPU ALU operations
#
# The SM83 ALU handles:
# - 8-bit arithmetic (ADD, ADC, SUB, SBC)
# - 8-bit logic (AND, OR, XOR, CP)
# - Rotates and shifts (RL, RR, RLC, RRC)
# - Special operations (DAA, CPL, SCF, CCF)
#
# Flag positions for Game Boy (Mode=3):
# - Bit 7: Z (Zero)
# - Bit 6: N (Subtract)
# - Bit 5: H (Half-carry)
# - Bit 4: C (Carry)
# - Bits 3-0: Always 0

RSpec.describe 'SM83 ALU' do
  before(:all) do
    begin
      require_relative '../../../../../examples/gameboy/gameboy'
      @gameboy_available = true
    rescue LoadError => e
      @gameboy_available = false
    end
  end

  before(:each) do
    skip 'GameBoy module not available' unless @gameboy_available
    @alu = GameBoy::SM83_ALU.new('test_alu')
    @alu.set_input(:clk, 0)
    @alu.set_input(:f_in, 0)
    @alu.set_input(:arith16, 0)
    @alu.set_input(:z16, 0)
  end

  # Helper to extract flag values
  def z_flag(f_out)
    (f_out >> 7) & 1
  end

  def n_flag(f_out)
    (f_out >> 6) & 1
  end

  def h_flag(f_out)
    (f_out >> 5) & 1
  end

  def c_flag(f_out)
    (f_out >> 4) & 1
  end

  # ==========================================================================
  # 8-bit Arithmetic Operations
  # ==========================================================================
  describe '8-bit Arithmetic Operations' do
    describe 'ADD (ALU_ADD = 0)' do
      it 'adds two positive numbers' do
        @alu.set_input(:a, 0x10)
        @alu.set_input(:b, 0x05)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_ADD)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x15)
        expect(z_flag(@alu.get_output(:f_out))).to eq(0)
        expect(n_flag(@alu.get_output(:f_out))).to eq(0)
      end

      it 'sets zero flag when result is zero' do
        @alu.set_input(:a, 0x00)
        @alu.set_input(:b, 0x00)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_ADD)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x00)
        expect(z_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'sets carry flag on overflow' do
        @alu.set_input(:a, 0xFF)
        @alu.set_input(:b, 0x01)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_ADD)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x00)
        expect(c_flag(@alu.get_output(:f_out))).to eq(1)
        expect(z_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'sets half-carry flag when carry from bit 3 to 4' do
        @alu.set_input(:a, 0x0F)
        @alu.set_input(:b, 0x01)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_ADD)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x10)
        expect(h_flag(@alu.get_output(:f_out))).to eq(1)
      end
    end

    describe 'ADC (ALU_ADC = 1)' do
      it 'adds two numbers with carry' do
        @alu.set_input(:a, 0x10)
        @alu.set_input(:b, 0x05)
        @alu.set_input(:f_in, 0x10)  # Carry flag set
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_ADC)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x16)
      end

      it 'adds two numbers without carry' do
        @alu.set_input(:a, 0x10)
        @alu.set_input(:b, 0x05)
        @alu.set_input(:f_in, 0x00)  # Carry flag clear
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_ADC)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x15)
      end
    end

    describe 'SUB (ALU_SUB = 2)' do
      it 'subtracts two positive numbers' do
        @alu.set_input(:a, 0x20)
        @alu.set_input(:b, 0x08)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_SUB)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x18)
        expect(n_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'sets zero flag when result is zero' do
        @alu.set_input(:a, 0x42)
        @alu.set_input(:b, 0x42)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_SUB)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x00)
        expect(z_flag(@alu.get_output(:f_out))).to eq(1)
        expect(n_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'sets carry flag on underflow' do
        @alu.set_input(:a, 0x00)
        @alu.set_input(:b, 0x01)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_SUB)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0xFF)
        expect(c_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'sets half-carry flag on borrow from bit 4' do
        @alu.set_input(:a, 0x10)
        @alu.set_input(:b, 0x01)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_SUB)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x0F)
        expect(h_flag(@alu.get_output(:f_out))).to eq(1)
      end
    end

    describe 'SBC (ALU_SBC = 3)' do
      it 'subtracts with borrow' do
        @alu.set_input(:a, 0x20)
        @alu.set_input(:b, 0x08)
        @alu.set_input(:f_in, 0x10)  # Carry flag set (borrow)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_SBC)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x17)
        expect(n_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'subtracts without borrow' do
        @alu.set_input(:a, 0x20)
        @alu.set_input(:b, 0x08)
        @alu.set_input(:f_in, 0x00)  # Carry flag clear
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_SBC)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x18)
      end
    end
  end

  # ==========================================================================
  # 8-bit Logic Operations
  # ==========================================================================
  describe '8-bit Logic Operations' do
    describe 'AND (ALU_AND = 4)' do
      it 'performs bitwise AND' do
        @alu.set_input(:a, 0xF0)
        @alu.set_input(:b, 0x0F)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_AND)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x00)
        expect(z_flag(@alu.get_output(:f_out))).to eq(1)
        expect(h_flag(@alu.get_output(:f_out))).to eq(1)  # AND always sets H
      end

      it 'performs bitwise AND with non-zero result' do
        @alu.set_input(:a, 0xFF)
        @alu.set_input(:b, 0xAA)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_AND)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0xAA)
        expect(z_flag(@alu.get_output(:f_out))).to eq(0)
        expect(h_flag(@alu.get_output(:f_out))).to eq(1)
      end
    end

    describe 'XOR (ALU_XOR = 5)' do
      it 'performs bitwise XOR' do
        @alu.set_input(:a, 0xFF)
        @alu.set_input(:b, 0xF0)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_XOR)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x0F)
        expect(z_flag(@alu.get_output(:f_out))).to eq(0)
      end

      it 'XOR A,A zeros the result' do
        @alu.set_input(:a, 0x42)
        @alu.set_input(:b, 0x42)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_XOR)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x00)
        expect(z_flag(@alu.get_output(:f_out))).to eq(1)
      end
    end

    describe 'OR (ALU_OR = 6)' do
      it 'performs bitwise OR' do
        @alu.set_input(:a, 0xF0)
        @alu.set_input(:b, 0x0F)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_OR)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0xFF)
        expect(z_flag(@alu.get_output(:f_out))).to eq(0)
      end

      it 'sets zero flag when both inputs are zero' do
        @alu.set_input(:a, 0x00)
        @alu.set_input(:b, 0x00)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_OR)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x00)
        expect(z_flag(@alu.get_output(:f_out))).to eq(1)
      end
    end

    describe 'CP (ALU_CP = 7)' do
      it 'compares two equal values (sets Z flag)' do
        @alu.set_input(:a, 0x42)
        @alu.set_input(:b, 0x42)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_CP)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x00)
        expect(z_flag(@alu.get_output(:f_out))).to eq(1)
        expect(n_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'compares two different values (clears Z flag)' do
        @alu.set_input(:a, 0x42)
        @alu.set_input(:b, 0x41)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_CP)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x01)
        expect(z_flag(@alu.get_output(:f_out))).to eq(0)
        expect(n_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'sets carry flag when B > A' do
        @alu.set_input(:a, 0x10)
        @alu.set_input(:b, 0x20)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_CP)
        @alu.propagate

        expect(c_flag(@alu.get_output(:f_out))).to eq(1)
      end
    end
  end

  # ==========================================================================
  # Rotate Operations
  # ==========================================================================
  describe 'Rotate Operations' do
    describe 'RLC (ALU_RLC = 8)' do
      it 'rotates left through carry (MSB to LSB and carry)' do
        @alu.set_input(:a, 0x80)  # 10000000
        @alu.set_input(:b, 0x00)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_RLC)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x01)  # 00000001
        expect(c_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'rotates value with bit 7 clear' do
        @alu.set_input(:a, 0x01)  # 00000001
        @alu.set_input(:b, 0x00)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_RLC)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x02)  # 00000010
        expect(c_flag(@alu.get_output(:f_out))).to eq(0)
      end
    end

    describe 'RRC (ALU_RRC = 9)' do
      it 'rotates right through carry (LSB to MSB and carry)' do
        @alu.set_input(:a, 0x01)  # 00000001
        @alu.set_input(:b, 0x00)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_RRC)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x80)  # 10000000
        expect(c_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'rotates value with bit 0 clear' do
        @alu.set_input(:a, 0x80)  # 10000000
        @alu.set_input(:b, 0x00)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_RRC)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x40)  # 01000000
        expect(c_flag(@alu.get_output(:f_out))).to eq(0)
      end
    end

    describe 'RL (ALU_RL = 10)' do
      it 'rotates left through carry flag' do
        @alu.set_input(:a, 0x80)  # 10000000
        @alu.set_input(:b, 0x00)
        @alu.set_input(:f_in, 0x10)  # Carry set
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_RL)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x01)  # Old carry becomes bit 0
        expect(c_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'rotates left with carry clear' do
        @alu.set_input(:a, 0x80)  # 10000000
        @alu.set_input(:b, 0x00)
        @alu.set_input(:f_in, 0x00)  # Carry clear
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_RL)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x00)  # Old carry (0) becomes bit 0
        expect(c_flag(@alu.get_output(:f_out))).to eq(1)
      end
    end

    describe 'RR (ALU_RR = 11)' do
      it 'rotates right through carry flag' do
        @alu.set_input(:a, 0x01)  # 00000001
        @alu.set_input(:b, 0x00)
        @alu.set_input(:f_in, 0x10)  # Carry set
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_RR)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x80)  # Old carry becomes bit 7
        expect(c_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'rotates right with carry clear' do
        @alu.set_input(:a, 0x01)  # 00000001
        @alu.set_input(:b, 0x00)
        @alu.set_input(:f_in, 0x00)  # Carry clear
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_RR)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x00)  # Old carry (0) becomes bit 7
        expect(c_flag(@alu.get_output(:f_out))).to eq(1)
      end
    end
  end

  # ==========================================================================
  # Special Operations
  # ==========================================================================
  describe 'Special Operations' do
    describe 'CPL (ALU_CPL = 13)' do
      it 'complements all bits of A' do
        @alu.set_input(:a, 0xAA)  # 10101010
        @alu.set_input(:b, 0x00)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_CPL)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x55)  # 01010101
        expect(n_flag(@alu.get_output(:f_out))).to eq(1)
        expect(h_flag(@alu.get_output(:f_out))).to eq(1)
      end

      it 'complements 0x00 to 0xFF' do
        @alu.set_input(:a, 0x00)
        @alu.set_input(:b, 0x00)
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_CPL)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0xFF)
      end
    end

    describe 'SCF (ALU_SCF = 14)' do
      it 'sets carry flag' do
        @alu.set_input(:a, 0x42)
        @alu.set_input(:b, 0x00)
        @alu.set_input(:f_in, 0x00)  # Carry clear
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_SCF)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x42)  # A unchanged
        expect(c_flag(@alu.get_output(:f_out))).to eq(1)
      end
    end

    describe 'CCF (ALU_CCF = 15)' do
      it 'complements carry flag (from set to clear)' do
        @alu.set_input(:a, 0x42)
        @alu.set_input(:b, 0x00)
        @alu.set_input(:f_in, 0x10)  # Carry set
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_CCF)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x42)  # A unchanged
        expect(c_flag(@alu.get_output(:f_out))).to eq(0)
      end

      it 'complements carry flag (from clear to set)' do
        @alu.set_input(:a, 0x42)
        @alu.set_input(:b, 0x00)
        @alu.set_input(:f_in, 0x00)  # Carry clear
        @alu.set_input(:op, GameBoy::SM83_ALU::ALU_CCF)
        @alu.propagate

        expect(@alu.get_output(:q)).to eq(0x42)  # A unchanged
        expect(c_flag(@alu.get_output(:f_out))).to eq(1)
      end
    end
  end

  # ==========================================================================
  # Flag Behavior
  # ==========================================================================
  describe 'Flag Behavior' do
    it 'lower 4 bits of flags output are always 0' do
      @alu.set_input(:a, 0xFF)
      @alu.set_input(:b, 0x01)
      @alu.set_input(:op, GameBoy::SM83_ALU::ALU_ADD)
      @alu.propagate

      f_out = @alu.get_output(:f_out)
      expect(f_out & 0x0F).to eq(0)
    end

    it 'N flag is set for subtraction operations' do
      [GameBoy::SM83_ALU::ALU_SUB, GameBoy::SM83_ALU::ALU_SBC, GameBoy::SM83_ALU::ALU_CP].each do |op|
        @alu.set_input(:a, 0x10)
        @alu.set_input(:b, 0x05)
        @alu.set_input(:op, op)
        @alu.propagate

        expect(n_flag(@alu.get_output(:f_out))).to eq(1), "Expected N flag set for op #{op}"
      end
    end

    it 'N flag is clear for non-subtraction operations' do
      [GameBoy::SM83_ALU::ALU_ADD, GameBoy::SM83_ALU::ALU_ADC,
       GameBoy::SM83_ALU::ALU_AND, GameBoy::SM83_ALU::ALU_OR,
       GameBoy::SM83_ALU::ALU_XOR].each do |op|
        @alu.set_input(:a, 0x10)
        @alu.set_input(:b, 0x05)
        @alu.set_input(:op, op)
        @alu.propagate

        expect(n_flag(@alu.get_output(:f_out))).to eq(0), "Expected N flag clear for op #{op}"
      end
    end
  end

  # ==========================================================================
  # Edge Cases
  # ==========================================================================
  describe 'Edge Cases' do
    it 'handles maximum values' do
      @alu.set_input(:a, 0xFF)
      @alu.set_input(:b, 0xFF)
      @alu.set_input(:op, GameBoy::SM83_ALU::ALU_ADD)
      @alu.propagate

      expect(@alu.get_output(:q)).to eq(0xFE)
      expect(c_flag(@alu.get_output(:f_out))).to eq(1)
    end

    it 'handles zero values' do
      @alu.set_input(:a, 0x00)
      @alu.set_input(:b, 0x00)
      @alu.set_input(:op, GameBoy::SM83_ALU::ALU_ADD)
      @alu.propagate

      expect(@alu.get_output(:q)).to eq(0x00)
      expect(z_flag(@alu.get_output(:f_out))).to eq(1)
      expect(c_flag(@alu.get_output(:f_out))).to eq(0)
    end
  end
end
