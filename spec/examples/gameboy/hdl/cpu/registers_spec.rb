# frozen_string_literal: true

require 'spec_helper'

# SM83 Registers Tests
# Tests the Game Boy CPU register file
#
# The SM83 register file contains:
# - AF: Accumulator and Flags
# - BC: General purpose
# - DE: General purpose
# - HL: General purpose / indirect addressing
# - SP: Stack pointer
# - PC: Program counter
#
# Note: No shadow registers (AF', BC', DE', HL') unlike Z80
# Note: No IX, IY index registers unlike Z80

RSpec.describe 'SM83 Registers' do
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
    @regs = GameBoy::SM83_Registers.new('test_regs')
    reset_all_write_enables
    @regs.set_input(:cen, 1)  # Clock enable
    @regs.set_input(:rst, 0)  # Not in reset
    @regs.set_input(:pc_inc, 0)
  end

  def reset_all_write_enables
    @regs.set_input(:we_a, 0)
    @regs.set_input(:we_f, 0)
    @regs.set_input(:we_b, 0)
    @regs.set_input(:we_c, 0)
    @regs.set_input(:we_d, 0)
    @regs.set_input(:we_e, 0)
    @regs.set_input(:we_h, 0)
    @regs.set_input(:we_l, 0)
    @regs.set_input(:we_sp_h, 0)
    @regs.set_input(:we_sp_l, 0)
    @regs.set_input(:we_pc, 0)
  end

  def clock_cycle
    @regs.set_input(:clk, 0)
    @regs.propagate
    @regs.set_input(:clk, 1)
    @regs.propagate
  end

  def reset_registers
    @regs.set_input(:rst, 1)
    clock_cycle
    @regs.set_input(:rst, 0)
  end

  # ==========================================================================
  # Reset Values (DMG Boot ROM values)
  # ==========================================================================
  describe 'Reset Values' do
    it 'resets A to 0x01 (DMG value)' do
      reset_registers
      expect(@regs.get_output(:acc_out)).to eq(0x01)
    end

    it 'resets F to 0xB0 (Z=1, N=0, H=1, C=1)' do
      reset_registers
      expect(@regs.get_output(:f_out)).to eq(0xB0)
    end

    it 'resets B to 0x00' do
      reset_registers
      expect(@regs.get_output(:b_out)).to eq(0x00)
    end

    it 'resets C to 0x13' do
      reset_registers
      expect(@regs.get_output(:c_out)).to eq(0x13)
    end

    it 'resets D to 0x00' do
      reset_registers
      expect(@regs.get_output(:d_out)).to eq(0x00)
    end

    it 'resets E to 0xD8' do
      reset_registers
      expect(@regs.get_output(:e_out)).to eq(0xD8)
    end

    it 'resets H to 0x01' do
      reset_registers
      expect(@regs.get_output(:h_out)).to eq(0x01)
    end

    it 'resets L to 0x4D' do
      reset_registers
      expect(@regs.get_output(:l_out)).to eq(0x4D)
    end

    it 'resets SP to 0xFFFE' do
      reset_registers
      expect(@regs.get_output(:sp_out)).to eq(0xFFFE)
    end

    it 'resets PC to 0x0100 (entry point after boot ROM)' do
      reset_registers
      expect(@regs.get_output(:pc_out)).to eq(0x0100)
    end
  end

  # ==========================================================================
  # 8-bit Register Writes
  # ==========================================================================
  describe '8-bit Register Writes' do
    before(:each) do
      reset_registers
    end

    describe 'Accumulator (A)' do
      it 'writes to A when we_a is set' do
        @regs.set_input(:di_a, 0x42)
        @regs.set_input(:we_a, 1)
        clock_cycle

        expect(@regs.get_output(:acc_out)).to eq(0x42)
      end

      it 'preserves A when we_a is clear' do
        initial_value = @regs.get_output(:acc_out)
        @regs.set_input(:di_a, 0x42)
        @regs.set_input(:we_a, 0)
        clock_cycle

        expect(@regs.get_output(:acc_out)).to eq(initial_value)
      end
    end

    describe 'Flags (F)' do
      it 'writes to F when we_f is set' do
        @regs.set_input(:di_f, 0xF0)
        @regs.set_input(:we_f, 1)
        clock_cycle

        expect(@regs.get_output(:f_out)).to eq(0xF0)
      end

      it 'masks lower 4 bits to 0 (Game Boy flags format)' do
        @regs.set_input(:di_f, 0xFF)  # All bits set
        @regs.set_input(:we_f, 1)
        clock_cycle

        expect(@regs.get_output(:f_out)).to eq(0xF0)  # Lower 4 bits masked
      end

      it 'preserves F when we_f is clear' do
        initial_value = @regs.get_output(:f_out)
        @regs.set_input(:di_f, 0x00)
        @regs.set_input(:we_f, 0)
        clock_cycle

        expect(@regs.get_output(:f_out)).to eq(initial_value)
      end
    end

    describe 'B Register' do
      it 'writes to B when we_b is set' do
        @regs.set_input(:di_b, 0xAB)
        @regs.set_input(:we_b, 1)
        clock_cycle

        expect(@regs.get_output(:b_out)).to eq(0xAB)
      end
    end

    describe 'C Register' do
      it 'writes to C when we_c is set' do
        @regs.set_input(:di_c, 0xCD)
        @regs.set_input(:we_c, 1)
        clock_cycle

        expect(@regs.get_output(:c_out)).to eq(0xCD)
      end
    end

    describe 'D Register' do
      it 'writes to D when we_d is set' do
        @regs.set_input(:di_d, 0x12)
        @regs.set_input(:we_d, 1)
        clock_cycle

        expect(@regs.get_output(:d_out)).to eq(0x12)
      end
    end

    describe 'E Register' do
      it 'writes to E when we_e is set' do
        @regs.set_input(:di_e, 0x34)
        @regs.set_input(:we_e, 1)
        clock_cycle

        expect(@regs.get_output(:e_out)).to eq(0x34)
      end
    end

    describe 'H Register' do
      it 'writes to H when we_h is set' do
        @regs.set_input(:di_h, 0x56)
        @regs.set_input(:we_h, 1)
        clock_cycle

        expect(@regs.get_output(:h_out)).to eq(0x56)
      end
    end

    describe 'L Register' do
      it 'writes to L when we_l is set' do
        @regs.set_input(:di_l, 0x78)
        @regs.set_input(:we_l, 1)
        clock_cycle

        expect(@regs.get_output(:l_out)).to eq(0x78)
      end
    end
  end

  # ==========================================================================
  # 16-bit Register Pair Outputs
  # ==========================================================================
  describe '16-bit Register Pair Outputs' do
    before(:each) do
      reset_registers
    end

    describe 'BC pair' do
      it 'outputs BC as concatenation of B and C' do
        @regs.set_input(:di_b, 0x12)
        @regs.set_input(:we_b, 1)
        @regs.set_input(:di_c, 0x34)
        @regs.set_input(:we_c, 1)
        clock_cycle

        expect(@regs.get_output(:bc_out)).to eq(0x1234)
      end
    end

    describe 'DE pair' do
      it 'outputs DE as concatenation of D and E' do
        @regs.set_input(:di_d, 0x56)
        @regs.set_input(:we_d, 1)
        @regs.set_input(:di_e, 0x78)
        @regs.set_input(:we_e, 1)
        clock_cycle

        expect(@regs.get_output(:de_out)).to eq(0x5678)
      end
    end

    describe 'HL pair' do
      it 'outputs HL as concatenation of H and L' do
        @regs.set_input(:di_h, 0x9A)
        @regs.set_input(:we_h, 1)
        @regs.set_input(:di_l, 0xBC)
        @regs.set_input(:we_l, 1)
        clock_cycle

        expect(@regs.get_output(:hl_out)).to eq(0x9ABC)
      end
    end
  end

  # ==========================================================================
  # Stack Pointer
  # ==========================================================================
  describe 'Stack Pointer' do
    before(:each) do
      reset_registers
    end

    it 'writes high byte of SP when we_sp_h is set' do
      @regs.set_input(:di_sp_h, 0xDE)
      @regs.set_input(:we_sp_h, 1)
      clock_cycle

      sp = @regs.get_output(:sp_out)
      expect(sp >> 8).to eq(0xDE)
    end

    it 'writes low byte of SP when we_sp_l is set' do
      @regs.set_input(:di_sp_l, 0xF0)
      @regs.set_input(:we_sp_l, 1)
      clock_cycle

      sp = @regs.get_output(:sp_out)
      expect(sp & 0xFF).to eq(0xF0)
    end

    it 'writes full 16-bit SP with separate high/low writes' do
      @regs.set_input(:di_sp_h, 0xCD)
      @regs.set_input(:we_sp_h, 1)
      clock_cycle

      reset_all_write_enables
      @regs.set_input(:di_sp_l, 0xEF)
      @regs.set_input(:we_sp_l, 1)
      clock_cycle

      expect(@regs.get_output(:sp_out)).to eq(0xCDEF)
    end
  end

  # ==========================================================================
  # Program Counter
  # ==========================================================================
  describe 'Program Counter' do
    before(:each) do
      reset_registers
    end

    it 'writes PC when we_pc is set' do
      @regs.set_input(:di_pc, 0x1234)
      @regs.set_input(:we_pc, 1)
      clock_cycle

      expect(@regs.get_output(:pc_out)).to eq(0x1234)
    end

    it 'increments PC when pc_inc is set' do
      initial_pc = @regs.get_output(:pc_out)
      @regs.set_input(:pc_inc, 1)
      clock_cycle

      expect(@regs.get_output(:pc_out)).to eq(initial_pc + 1)
    end

    it 'increments PC multiple times' do
      initial_pc = @regs.get_output(:pc_out)
      @regs.set_input(:pc_inc, 1)
      3.times { clock_cycle }

      expect(@regs.get_output(:pc_out)).to eq(initial_pc + 3)
    end

    it 'wraps PC on overflow' do
      @regs.set_input(:di_pc, 0xFFFF)
      @regs.set_input(:we_pc, 1)
      clock_cycle

      reset_all_write_enables
      @regs.set_input(:pc_inc, 1)
      clock_cycle

      expect(@regs.get_output(:pc_out)).to eq(0x0000)
    end

    it 'write takes precedence over increment' do
      @regs.set_input(:di_pc, 0x4000)
      @regs.set_input(:we_pc, 1)
      @regs.set_input(:pc_inc, 1)
      clock_cycle

      expect(@regs.get_output(:pc_out)).to eq(0x4000)
    end
  end

  # ==========================================================================
  # Clock Enable
  # ==========================================================================
  describe 'Clock Enable' do
    before(:each) do
      reset_registers
    end

    it 'does not update registers when cen is disabled' do
      initial_a = @regs.get_output(:acc_out)
      @regs.set_input(:di_a, 0xFF)
      @regs.set_input(:we_a, 1)
      @regs.set_input(:cen, 0)
      clock_cycle

      expect(@regs.get_output(:acc_out)).to eq(initial_a)
    end

    it 'updates registers when cen is enabled' do
      @regs.set_input(:di_a, 0xFF)
      @regs.set_input(:we_a, 1)
      @regs.set_input(:cen, 1)
      clock_cycle

      expect(@regs.get_output(:acc_out)).to eq(0xFF)
    end
  end

  # ==========================================================================
  # Multiple Register Writes
  # ==========================================================================
  describe 'Multiple Register Writes' do
    before(:each) do
      reset_registers
    end

    it 'writes multiple registers in single clock cycle' do
      @regs.set_input(:di_a, 0x11)
      @regs.set_input(:we_a, 1)
      @regs.set_input(:di_b, 0x22)
      @regs.set_input(:we_b, 1)
      @regs.set_input(:di_c, 0x33)
      @regs.set_input(:we_c, 1)
      clock_cycle

      expect(@regs.get_output(:acc_out)).to eq(0x11)
      expect(@regs.get_output(:b_out)).to eq(0x22)
      expect(@regs.get_output(:c_out)).to eq(0x33)
    end

    it 'maintains registers not being written' do
      @regs.set_input(:di_a, 0x99)
      @regs.set_input(:we_a, 1)
      clock_cycle

      initial_a = @regs.get_output(:acc_out)
      reset_all_write_enables
      @regs.set_input(:di_b, 0xAA)
      @regs.set_input(:we_b, 1)
      clock_cycle

      expect(@regs.get_output(:acc_out)).to eq(initial_a)
      expect(@regs.get_output(:b_out)).to eq(0xAA)
    end
  end

  # ==========================================================================
  # Edge Cases
  # ==========================================================================
  describe 'Edge Cases' do
    before(:each) do
      reset_registers
    end

    it 'handles all zeros' do
      @regs.set_input(:di_a, 0x00)
      @regs.set_input(:we_a, 1)
      @regs.set_input(:di_f, 0x00)
      @regs.set_input(:we_f, 1)
      clock_cycle

      expect(@regs.get_output(:acc_out)).to eq(0x00)
      expect(@regs.get_output(:f_out)).to eq(0x00)
    end

    it 'handles all ones' do
      @regs.set_input(:di_a, 0xFF)
      @regs.set_input(:we_a, 1)
      clock_cycle

      expect(@regs.get_output(:acc_out)).to eq(0xFF)
    end

    it 'handles alternating bits' do
      @regs.set_input(:di_a, 0xAA)
      @regs.set_input(:we_a, 1)
      clock_cycle

      expect(@regs.get_output(:acc_out)).to eq(0xAA)

      @regs.set_input(:di_a, 0x55)
      clock_cycle

      expect(@regs.get_output(:acc_out)).to eq(0x55)
    end
  end

  # ==========================================================================
  # Individual Register Outputs
  # ==========================================================================
  describe 'Individual Register Outputs' do
    before(:each) do
      reset_registers
    end

    it 'provides individual B output' do
      @regs.set_input(:di_b, 0xBB)
      @regs.set_input(:we_b, 1)
      clock_cycle

      expect(@regs.get_output(:b_out)).to eq(0xBB)
    end

    it 'provides individual C output' do
      @regs.set_input(:di_c, 0xCC)
      @regs.set_input(:we_c, 1)
      clock_cycle

      expect(@regs.get_output(:c_out)).to eq(0xCC)
    end

    it 'provides individual D output' do
      @regs.set_input(:di_d, 0xDD)
      @regs.set_input(:we_d, 1)
      clock_cycle

      expect(@regs.get_output(:d_out)).to eq(0xDD)
    end

    it 'provides individual E output' do
      @regs.set_input(:di_e, 0xEE)
      @regs.set_input(:we_e, 1)
      clock_cycle

      expect(@regs.get_output(:e_out)).to eq(0xEE)
    end

    it 'provides individual H output' do
      @regs.set_input(:di_h, 0xAA)
      @regs.set_input(:we_h, 1)
      clock_cycle

      expect(@regs.get_output(:h_out)).to eq(0xAA)
    end

    it 'provides individual L output' do
      @regs.set_input(:di_l, 0xBB)
      @regs.set_input(:we_l, 1)
      clock_cycle

      expect(@regs.get_output(:l_out)).to eq(0xBB)
    end
  end
end
