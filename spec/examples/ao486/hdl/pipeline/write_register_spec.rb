require_relative '../../spec_helper'
require_relative '../../../../../examples/ao486/hdl/pipeline/write_register'

RSpec.describe RHDL::Examples::AO486::WriteRegister do
  C = RHDL::Examples::AO486::Constants
  let(:reg) { RHDL::Examples::AO486::WriteRegister.new }

  def reset!(r)
    r.set_input(:clk, 0)
    r.set_input(:rst_n, 0)
    r.propagate
    r.set_input(:clk, 1)
    r.propagate
    r.set_input(:rst_n, 1)
  end

  def clock!(r)
    r.set_input(:clk, 0)
    r.propagate
    r.set_input(:clk, 1)
    r.propagate
  end

  describe 'GPR reset values' do
    it 'resets GPRs to startup defaults' do
      reset!(reg)
      expect(reg.get_output(:eax)).to eq(C::STARTUP_EAX)
      expect(reg.get_output(:ebx)).to eq(C::STARTUP_EBX)
      expect(reg.get_output(:ecx)).to eq(C::STARTUP_ECX)
      expect(reg.get_output(:edx)).to eq(C::STARTUP_EDX)
      expect(reg.get_output(:esp)).to eq(C::STARTUP_ESP)
      expect(reg.get_output(:ebp)).to eq(C::STARTUP_EBP)
      expect(reg.get_output(:esi)).to eq(C::STARTUP_ESI)
      expect(reg.get_output(:edi)).to eq(C::STARTUP_EDI)
    end
  end

  describe 'GPR writes' do
    before { reset!(reg) }

    it 'writes 32-bit value to EAX via write_eax' do
      reg.set_input(:write_eax, 1)
      reg.set_input(:result, 0x1234_5678)
      reg.set_input(:wr_operand_32bit, 1)
      clock!(reg)
      expect(reg.get_output(:eax)).to eq(0x1234_5678)
    end

    it 'writes 16-bit value preserving high word' do
      # First write 32-bit
      reg.set_input(:write_eax, 1)
      reg.set_input(:result, 0xAAAA_BBBB)
      reg.set_input(:wr_operand_32bit, 1)
      clock!(reg)

      # Now write 16-bit
      reg.set_input(:write_eax, 1)
      reg.set_input(:result, 0x0000_1234)
      reg.set_input(:wr_operand_32bit, 0)
      reg.set_input(:wr_is_8bit, 0)
      clock!(reg)
      expect(reg.get_output(:eax)).to eq(0xAAAA_1234)
    end

    it 'writes to specific register via write_regrm with reg index' do
      reg.set_input(:write_regrm, 1)
      reg.set_input(:wr_dst_is_reg, 1)
      reg.set_input(:wr_modregrm_reg, 1)  # ECX
      reg.set_input(:result, 0xDEAD_BEEF)
      reg.set_input(:wr_operand_32bit, 1)
      clock!(reg)
      expect(reg.get_output(:ecx)).to eq(0xDEAD_BEEF)
    end
  end

  describe 'EFLAGS' do
    before { reset!(reg) }

    it 'resets flags to startup defaults' do
      expect(reg.get_output(:cflag)).to eq(C::STARTUP_CFLAG)
      expect(reg.get_output(:zflag)).to eq(C::STARTUP_ZFLAG)
      expect(reg.get_output(:sflag)).to eq(C::STARTUP_SFLAG)
      expect(reg.get_output(:oflag)).to eq(C::STARTUP_OFLAG)
      expect(reg.get_output(:dflag)).to eq(C::STARTUP_DFLAG)
      expect(reg.get_output(:iflag)).to eq(C::STARTUP_IFLAG)
      expect(reg.get_output(:iopl)).to eq(C::STARTUP_IOPL)
    end

    it 'updates flags via write_flags' do
      reg.set_input(:write_flags, 1)
      reg.set_input(:cflag_to_reg, 1)
      reg.set_input(:zflag_to_reg, 1)
      reg.set_input(:sflag_to_reg, 0)
      reg.set_input(:oflag_to_reg, 1)
      clock!(reg)
      expect(reg.get_output(:cflag)).to eq(1)
      expect(reg.get_output(:zflag)).to eq(1)
      expect(reg.get_output(:sflag)).to eq(0)
      expect(reg.get_output(:oflag)).to eq(1)
    end
  end

  describe 'CR0 and mode detection' do
    before { reset!(reg) }

    it 'resets CR0 bits to startup defaults' do
      expect(reg.get_output(:cr0_pe)).to eq(0)  # real mode
      expect(reg.get_output(:cr0_pg)).to eq(0)
    end

    it 'computes real_mode when PE=0' do
      expect(reg.get_output(:real_mode)).to eq(1)
      expect(reg.get_output(:protected_mode)).to eq(0)
      expect(reg.get_output(:v8086_mode)).to eq(0)
    end

    it 'computes protected_mode when PE=1 and VM=0' do
      reg.set_input(:write_cr0_pe, 1)
      reg.set_input(:cr0_pe_to_reg, 1)
      clock!(reg)
      expect(reg.get_output(:cr0_pe)).to eq(1)
      expect(reg.get_output(:real_mode)).to eq(0)
      expect(reg.get_output(:protected_mode)).to eq(1)
      expect(reg.get_output(:v8086_mode)).to eq(0)
    end
  end

  describe 'segment registers' do
    before { reset!(reg) }

    it 'resets CS to startup value' do
      expect(reg.get_output(:cs)).to eq(C::STARTUP_CS)
    end

    it 'resets segment RPLs to startup values' do
      expect(reg.get_output(:cs_rpl)).to eq(C::STARTUP_CS_RPL)
      expect(reg.get_output(:es_rpl)).to eq(C::STARTUP_ES_RPL)
    end

    it 'provides CPL output from cs_rpl' do
      expect(reg.get_output(:cpl)).to eq(C::STARTUP_CS_RPL)
    end

    it 'writes segment register via write_seg' do
      reg.set_input(:write_seg, 1)
      reg.set_input(:wr_seg_index, C::SEGMENT_DS)
      reg.set_input(:seg_to_reg, 0x0023)
      clock!(reg)
      expect(reg.get_output(:ds)).to eq(0x0023)
    end
  end

  describe 'EIP' do
    before { reset!(reg) }

    it 'resets EIP to startup value' do
      expect(reg.get_output(:eip)).to eq(C::STARTUP_EIP)
    end

    it 'updates EIP via write_eip' do
      reg.set_input(:write_eip, 1)
      reg.set_input(:eip_to_reg, 0x0010_0000)
      clock!(reg)
      expect(reg.get_output(:eip)).to eq(0x0010_0000)
    end
  end

  describe 'GDTR and IDTR' do
    before { reset!(reg) }

    it 'resets GDTR/IDTR to startup defaults' do
      expect(reg.get_output(:gdtr_base)).to eq(C::STARTUP_GDTR_BASE)
      expect(reg.get_output(:gdtr_limit)).to eq(C::STARTUP_GDTR_LIMIT)
      expect(reg.get_output(:idtr_base)).to eq(C::STARTUP_IDTR_BASE)
      expect(reg.get_output(:idtr_limit)).to eq(C::STARTUP_IDTR_LIMIT)
    end
  end
end
