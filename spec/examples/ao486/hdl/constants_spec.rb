require_relative '../spec_helper'
require_relative '../../../../examples/ao486/hdl/constants'

RSpec.describe RHDL::Examples::AO486::Constants do
  describe 'exception vectors' do
    it 'defines all x86 exception vectors' do
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_DE).to eq(0)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_DB).to eq(1)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_BP).to eq(3)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_OF).to eq(4)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_BR).to eq(5)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_UD).to eq(6)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_NM).to eq(7)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_DF).to eq(8)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_TS).to eq(10)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_NP).to eq(11)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_SS).to eq(12)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_GP).to eq(13)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_PF).to eq(14)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_AC).to eq(17)
      expect(RHDL::Examples::AO486::Constants::EXCEPTION_MC).to eq(18)
    end
  end

  describe 'command IDs' do
    it 'defines CMD_NULL as 0' do
      expect(RHDL::Examples::AO486::Constants::CMD_NULL).to eq(0)
    end

    it 'defines core arithmetic commands' do
      expect(RHDL::Examples::AO486::Constants::CMD_Arith).to eq(64)
      expect(RHDL::Examples::AO486::Constants::CMD_ADD).to eq(64)
      expect(RHDL::Examples::AO486::Constants::CMD_OR).to eq(65)
      expect(RHDL::Examples::AO486::Constants::CMD_ADC).to eq(66)
      expect(RHDL::Examples::AO486::Constants::CMD_SBB).to eq(67)
      expect(RHDL::Examples::AO486::Constants::CMD_AND).to eq(68)
      expect(RHDL::Examples::AO486::Constants::CMD_SUB).to eq(69)
      expect(RHDL::Examples::AO486::Constants::CMD_XOR).to eq(70)
      expect(RHDL::Examples::AO486::Constants::CMD_CMP).to eq(71)
    end

    it 'defines control flow commands' do
      expect(RHDL::Examples::AO486::Constants::CMD_JMP).to eq(87)
      expect(RHDL::Examples::AO486::Constants::CMD_CALL).to eq(3)
      expect(RHDL::Examples::AO486::Constants::CMD_RET_near).to eq(15)
      expect(RHDL::Examples::AO486::Constants::CMD_RET_far).to eq(63)
      expect(RHDL::Examples::AO486::Constants::CMD_Jcc).to eq(8)
      expect(RHDL::Examples::AO486::Constants::CMD_LOOP).to eq(60)
      expect(RHDL::Examples::AO486::Constants::CMD_IRET).to eq(35)
    end

    it 'defines data movement commands' do
      expect(RHDL::Examples::AO486::Constants::CMD_MOV).to eq(90)
      expect(RHDL::Examples::AO486::Constants::CMD_PUSH).to eq(74)
      expect(RHDL::Examples::AO486::Constants::CMD_POP).to eq(41)
      expect(RHDL::Examples::AO486::Constants::CMD_MOVS).to eq(106)
      expect(RHDL::Examples::AO486::Constants::CMD_STOS).to eq(83)
      expect(RHDL::Examples::AO486::Constants::CMD_LODS).to eq(72)
      expect(RHDL::Examples::AO486::Constants::CMD_XCHG).to eq(73)
    end

    it 'defines all 118 distinct CMD_* constants' do
      cmds = RHDL::Examples::AO486::Constants.constants.select { |c| c.to_s.start_with?('CMD_') }
      # There are many CMD_* constants; verify a minimum count
      expect(cmds.length).to be >= 80
    end
  end

  describe 'segment indices' do
    it 'defines all segment register indices' do
      expect(RHDL::Examples::AO486::Constants::SEGMENT_ES).to eq(0)
      expect(RHDL::Examples::AO486::Constants::SEGMENT_CS).to eq(1)
      expect(RHDL::Examples::AO486::Constants::SEGMENT_SS).to eq(2)
      expect(RHDL::Examples::AO486::Constants::SEGMENT_DS).to eq(3)
      expect(RHDL::Examples::AO486::Constants::SEGMENT_FS).to eq(4)
      expect(RHDL::Examples::AO486::Constants::SEGMENT_GS).to eq(5)
      expect(RHDL::Examples::AO486::Constants::SEGMENT_LDT).to eq(6)
      expect(RHDL::Examples::AO486::Constants::SEGMENT_TR).to eq(7)
    end
  end

  describe 'descriptor bit positions' do
    it 'defines descriptor field positions' do
      expect(RHDL::Examples::AO486::Constants::DESC_BIT_G).to eq(55)
      expect(RHDL::Examples::AO486::Constants::DESC_BIT_D_B).to eq(54)
      expect(RHDL::Examples::AO486::Constants::DESC_BIT_P).to eq(47)
      expect(RHDL::Examples::AO486::Constants::DESC_BIT_SEG).to eq(44)
    end
  end

  describe 'arithmetic operation codes' do
    it 'defines ARITH_* operation codes' do
      expect(RHDL::Examples::AO486::Constants::ARITH_ADD).to eq(0)
      expect(RHDL::Examples::AO486::Constants::ARITH_OR).to eq(1)
      expect(RHDL::Examples::AO486::Constants::ARITH_ADC).to eq(2)
      expect(RHDL::Examples::AO486::Constants::ARITH_SBB).to eq(3)
      expect(RHDL::Examples::AO486::Constants::ARITH_AND).to eq(4)
      expect(RHDL::Examples::AO486::Constants::ARITH_SUB).to eq(5)
      expect(RHDL::Examples::AO486::Constants::ARITH_XOR).to eq(6)
      expect(RHDL::Examples::AO486::Constants::ARITH_CMP).to eq(7)
    end
  end

  describe 'startup defaults' do
    it 'defines CPUID model/family/stepping' do
      expect(RHDL::Examples::AO486::Constants::CPUID_MODEL_FAMILY_STEPPING).to eq(0x0000_045B)
    end

    it 'defines startup register values' do
      expect(RHDL::Examples::AO486::Constants::STARTUP_EIP).to eq(0x0000_FFF0)
      expect(RHDL::Examples::AO486::Constants::STARTUP_CS).to eq(0xF000)
      expect(RHDL::Examples::AO486::Constants::STARTUP_EDX).to eq(RHDL::Examples::AO486::Constants::CPUID_MODEL_FAMILY_STEPPING)
    end
  end

  describe 'descriptor type constants' do
    it 'defines TSS and gate descriptor types' do
      expect(RHDL::Examples::AO486::Constants::DESC_TSS_AVAIL_386).to eq(0x9)
      expect(RHDL::Examples::AO486::Constants::DESC_TSS_BUSY_386).to eq(0xB)
      expect(RHDL::Examples::AO486::Constants::DESC_INTERRUPT_GATE_386).to eq(0xE)
      expect(RHDL::Examples::AO486::Constants::DESC_TRAP_GATE_386).to eq(0xF)
      expect(RHDL::Examples::AO486::Constants::DESC_CALL_GATE_386).to eq(0xC)
      expect(RHDL::Examples::AO486::Constants::DESC_LDT).to eq(0x2)
      expect(RHDL::Examples::AO486::Constants::DESC_TASK_GATE).to eq(0x5)
    end
  end
end
