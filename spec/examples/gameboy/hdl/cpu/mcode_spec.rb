# frozen_string_literal: true

require 'spec_helper'

# SM83 Microcode Tests
# Tests the Game Boy CPU instruction decoder and control signal generation
#
# The SM83 MCode module decodes instructions and generates control signals
# for each machine cycle and T-state of instruction execution.

RSpec.describe 'SM83 MCode' do
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
    @mcode = RHDL::Examples::GameBoy::SM83_MCode.new('test_mcode')
    @mcode.set_input(:clk, 0)
    @mcode.set_input(:i_set, 0)      # Normal instruction set
    @mcode.set_input(:m_cycle, 1)    # First machine cycle
    @mcode.set_input(:flags, 0)
    @mcode.set_input(:nmi_cycle, 0)
    @mcode.set_input(:int_cycle, 0)
    @mcode.set_input(:xy_state, 0)
  end

  # ==========================================================================
  # Default Values
  # ==========================================================================
  describe 'Default Values' do
    it 'sets default machine cycles to 1' do
      @mcode.set_input(:ir, 0x00)  # NOP
      @mcode.propagate

      expect(@mcode.get_output(:m_cycles)).to eq(1)
    end

    it 'sets default T-states to 4 for Game Boy' do
      @mcode.set_input(:ir, 0x00)  # NOP
      @mcode.propagate

      expect(@mcode.get_output(:t_states)).to eq(4)
    end

    it 'defaults all control signals to inactive' do
      @mcode.set_input(:ir, 0x00)
      @mcode.propagate

      expect(@mcode.get_output(:iorq)).to eq(0)
      expect(@mcode.get_output(:jump)).to eq(0)
      expect(@mcode.get_output(:call_out)).to eq(0)
      expect(@mcode.get_output(:write_sig)).to eq(0)
    end
  end

  # ==========================================================================
  # CB Prefix Detection
  # ==========================================================================
  describe 'CB Prefix Detection' do
    it 'detects CB prefix instruction' do
      @mcode.set_input(:ir, 0xCB)
      @mcode.propagate

      expect(@mcode.get_output(:prefix)).to eq(1)
    end

    it 'does not set prefix for non-CB instructions' do
      @mcode.set_input(:ir, 0x00)  # NOP
      @mcode.propagate

      expect(@mcode.get_output(:prefix)).to eq(0)
    end

    it 'does not set prefix for regular instructions' do
      [0x3E, 0x06, 0x0E, 0x80, 0x90].each do |opcode|
        @mcode.set_input(:ir, opcode)
        @mcode.propagate

        expect(@mcode.get_output(:prefix)).to eq(0), "Expected no prefix for opcode 0x#{opcode.to_s(16).upcase}"
      end
    end
  end

  # ==========================================================================
  # Control Instructions
  # ==========================================================================
  describe 'Control Instructions' do
    describe 'HALT (0x76)' do
      it 'sets halt signal' do
        @mcode.set_input(:ir, 0x76)
        @mcode.set_input(:i_set, 0)  # Normal instruction set
        @mcode.propagate

        expect(@mcode.get_output(:halt_sig)).to eq(1)
      end

      it 'does not set halt for non-HALT opcodes' do
        @mcode.set_input(:ir, 0x00)  # NOP
        @mcode.propagate

        expect(@mcode.get_output(:halt_sig)).to eq(0)
      end
    end

    describe 'STOP (0x10)' do
      it 'sets i_djnz signal for STOP instruction' do
        @mcode.set_input(:ir, 0x10)
        @mcode.set_input(:i_set, 0)
        @mcode.propagate

        expect(@mcode.get_output(:i_djnz)).to eq(1)
      end
    end

    describe 'DI (0xF3)' do
      it 'sets set_di signal to disable interrupts' do
        @mcode.set_input(:ir, 0xF3)
        @mcode.set_input(:i_set, 0)
        @mcode.propagate

        expect(@mcode.get_output(:set_di)).to eq(1)
      end
    end

    describe 'EI (0xFB)' do
      it 'sets set_ei signal to enable interrupts' do
        @mcode.set_input(:ir, 0xFB)
        @mcode.set_input(:i_set, 0)
        @mcode.propagate

        expect(@mcode.get_output(:set_ei)).to eq(1)
      end
    end
  end

  # ==========================================================================
  # Flag Manipulation Instructions
  # ==========================================================================
  describe 'Flag Manipulation Instructions' do
    describe 'CPL (0x2F)' do
      it 'sets i_cpl signal' do
        @mcode.set_input(:ir, 0x2F)
        @mcode.set_input(:i_set, 0)
        @mcode.propagate

        expect(@mcode.get_output(:i_cpl)).to eq(1)
      end
    end

    describe 'CCF (0x3F)' do
      it 'sets i_ccf signal' do
        @mcode.set_input(:ir, 0x3F)
        @mcode.set_input(:i_set, 0)
        @mcode.propagate

        expect(@mcode.get_output(:i_ccf)).to eq(1)
      end
    end

    describe 'SCF (0x37)' do
      it 'sets i_scf signal' do
        @mcode.set_input(:ir, 0x37)
        @mcode.set_input(:i_set, 0)
        @mcode.propagate

        expect(@mcode.get_output(:i_scf)).to eq(1)
      end
    end
  end

  # ==========================================================================
  # Return Instructions
  # ==========================================================================
  describe 'Return Instructions' do
    describe 'RETI (0xD9)' do
      it 'sets i_retn signal' do
        @mcode.set_input(:ir, 0xD9)
        @mcode.set_input(:i_set, 0)
        @mcode.propagate

        expect(@mcode.get_output(:i_retn)).to eq(1)
      end
    end
  end

  # ==========================================================================
  # Stack Pointer Instructions
  # ==========================================================================
  describe 'Stack Pointer Instructions' do
    describe 'LD SP,HL (0xF9)' do
      it 'sets ldsphl signal' do
        @mcode.set_input(:ir, 0xF9)
        @mcode.set_input(:i_set, 0)
        @mcode.propagate

        expect(@mcode.get_output(:ldsphl)).to eq(1)
      end
    end

    describe 'LD HL,SP+n (0xF8)' do
      it 'sets ldhlsp signal' do
        @mcode.set_input(:ir, 0xF8)
        @mcode.set_input(:i_set, 0)
        @mcode.propagate

        expect(@mcode.get_output(:ldhlsp)).to eq(1)
      end
    end

    describe 'ADD SP,dd (0xE8)' do
      it 'sets addsp_dd signal' do
        @mcode.set_input(:ir, 0xE8)
        @mcode.set_input(:i_set, 0)
        @mcode.propagate

        expect(@mcode.get_output(:addsp_dd)).to eq(1)
      end
    end
  end

  # ==========================================================================
  # PC Increment
  # ==========================================================================
  describe 'PC Increment' do
    it 'increments PC during first machine cycle' do
      @mcode.set_input(:ir, 0x00)
      @mcode.set_input(:m_cycle, 1)
      @mcode.propagate

      expect(@mcode.get_output(:inc_pc)).to eq(1)
    end

    it 'does not increment PC during other machine cycles' do
      @mcode.set_input(:ir, 0x00)
      @mcode.set_input(:m_cycle, 2)
      @mcode.propagate

      expect(@mcode.get_output(:inc_pc)).to eq(0)
    end
  end

  # ==========================================================================
  # Read/Write Control
  # ==========================================================================
  describe 'Read/Write Control' do
    it 'defaults to allowing reads' do
      @mcode.set_input(:ir, 0x00)
      @mcode.propagate

      expect(@mcode.get_output(:no_read)).to eq(0)
    end

    it 'defaults to no writes' do
      @mcode.set_input(:ir, 0x00)
      @mcode.propagate

      expect(@mcode.get_output(:write_sig)).to eq(0)
    end
  end

  # ==========================================================================
  # Instruction Set Modes
  # ==========================================================================
  describe 'Instruction Set Modes' do
    it 'handles normal instruction set (i_set=0)' do
      @mcode.set_input(:ir, 0x76)  # HALT
      @mcode.set_input(:i_set, 0)
      @mcode.propagate

      expect(@mcode.get_output(:halt_sig)).to eq(1)
    end

    it 'does not decode normal instructions in CB prefix mode' do
      @mcode.set_input(:ir, 0x76)  # HALT opcode, but in CB prefix mode
      @mcode.set_input(:i_set, 1)  # CB prefix mode
      @mcode.propagate

      expect(@mcode.get_output(:halt_sig)).to eq(0)
    end
  end

  # ==========================================================================
  # Special Signals
  # ==========================================================================
  describe 'Special Signals' do
    it 'has exchange signals disabled (unused in GB)' do
      @mcode.set_input(:ir, 0x00)
      @mcode.propagate

      expect(@mcode.get_output(:exchange_dh)).to eq(0)
      expect(@mcode.get_output(:exchange_rp)).to eq(0)
      expect(@mcode.get_output(:exchange_af)).to eq(0)
      expect(@mcode.get_output(:exchange_rs)).to eq(0)
    end

    it 'has block transfer signals disabled (unused in GB)' do
      @mcode.set_input(:ir, 0x00)
      @mcode.propagate

      expect(@mcode.get_output(:i_bt)).to eq(0)
      expect(@mcode.get_output(:i_bc)).to eq(0)
      expect(@mcode.get_output(:i_btr)).to eq(0)
    end

    it 'has RLD/RRD signals disabled (unused in GB)' do
      @mcode.set_input(:ir, 0x00)
      @mcode.propagate

      expect(@mcode.get_output(:i_rld)).to eq(0)
      expect(@mcode.get_output(:i_rrd)).to eq(0)
    end
  end

  # ==========================================================================
  # Mutual Exclusivity
  # ==========================================================================
  describe 'Signal Mutual Exclusivity' do
    it 'only one special instruction signal is active at a time' do
      special_opcodes = {
        0x76 => :halt_sig,
        0x10 => :i_djnz,
        0xF3 => :set_di,
        0xFB => :set_ei,
        0x2F => :i_cpl,
        0x3F => :i_ccf,
        0x37 => :i_scf,
        0xD9 => :i_retn,
        0xF9 => :ldsphl,
        0xF8 => :ldhlsp,
        0xE8 => :addsp_dd
      }

      special_opcodes.each do |opcode, expected_signal|
        @mcode.set_input(:ir, opcode)
        @mcode.set_input(:i_set, 0)
        @mcode.propagate

        special_opcodes.each_value do |signal|
          if signal == expected_signal
            expect(@mcode.get_output(signal)).to eq(1),
              "Expected #{signal} to be 1 for opcode 0x#{opcode.to_s(16).upcase}"
          else
            expect(@mcode.get_output(signal)).to eq(0),
              "Expected #{signal} to be 0 for opcode 0x#{opcode.to_s(16).upcase}"
          end
        end
      end
    end
  end

  # ==========================================================================
  # NOP Instruction
  # ==========================================================================
  describe 'NOP Instruction (0x00)' do
    it 'does not set any special signals' do
      @mcode.set_input(:ir, 0x00)
      @mcode.set_input(:i_set, 0)
      @mcode.propagate

      expect(@mcode.get_output(:halt_sig)).to eq(0)
      expect(@mcode.get_output(:i_djnz)).to eq(0)
      expect(@mcode.get_output(:set_di)).to eq(0)
      expect(@mcode.get_output(:set_ei)).to eq(0)
      expect(@mcode.get_output(:i_cpl)).to eq(0)
      expect(@mcode.get_output(:i_ccf)).to eq(0)
      expect(@mcode.get_output(:i_scf)).to eq(0)
    end

    it 'does not generate prefix' do
      @mcode.set_input(:ir, 0x00)
      @mcode.propagate

      expect(@mcode.get_output(:prefix)).to eq(0)
    end
  end
end
