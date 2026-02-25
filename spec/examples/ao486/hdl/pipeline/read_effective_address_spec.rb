# spec/examples/ao486/hdl/pipeline/read_effective_address_spec.rb
# RED spec for ReadEffectiveAddress combinational component

require 'rspec'
require_relative '../../../../../examples/ao486/hdl/pipeline/read_effective_address'
require_relative '../../../../../examples/ao486/hdl/constants'

C = RHDL::Examples::AO486::Constants unless defined?(C)

RSpec.describe RHDL::Examples::AO486::ReadEffectiveAddress do
  let(:ea) { described_class.new(:ea) }

  def set_regs(eax: 0, ecx: 0, edx: 0, ebx: 0, esp: 0, ebp: 0, esi: 0, edi: 0)
    ea.set_input(:reg_eax, eax)
    ea.set_input(:reg_ecx, ecx)
    ea.set_input(:reg_edx, edx)
    ea.set_input(:reg_ebx, ebx)
    ea.set_input(:reg_esp, esp)
    ea.set_input(:reg_ebp, ebp)
    ea.set_input(:reg_esi, esi)
    ea.set_input(:reg_edi, edi)
  end

  def calc_ea(mod:, rm:, addr32:, sib: 0, disp: 0, seg_base: 0, **regs)
    set_regs(**regs)
    ea.set_input(:modregrm_mod, mod)
    ea.set_input(:modregrm_rm, rm)
    ea.set_input(:address_32bit, addr32 ? 1 : 0)
    ea.set_input(:sib, sib)
    ea.set_input(:displacement, disp)
    ea.set_input(:seg_base, seg_base)
    ea.propagate
    { address: ea.get_output(:address), is_memory: ea.get_output(:is_memory),
      use_ss: ea.get_output(:use_ss) }
  end

  context '16-bit addressing' do
    it '[BX+SI] (mod=0, rm=0)' do
      result = calc_ea(mod: 0, rm: 0, addr32: false, ebx: 0x100, esi: 0x200, seg_base: 0x1000)
      expect(result[:is_memory]).to eq(1)
      expect(result[:address]).to eq(0x1000 + 0x0300)
      expect(result[:use_ss]).to eq(0)
    end

    it '[BX+DI] (mod=0, rm=1)' do
      result = calc_ea(mod: 0, rm: 1, addr32: false, ebx: 0x100, edi: 0x50, seg_base: 0)
      expect(result[:address]).to eq(0x150)
      expect(result[:use_ss]).to eq(0)
    end

    it '[BP+SI] uses SS (mod=0, rm=2)' do
      result = calc_ea(mod: 0, rm: 2, addr32: false, ebp: 0x400, esi: 0x10, seg_base: 0x2000)
      expect(result[:address]).to eq(0x2000 + 0x0410)
      expect(result[:use_ss]).to eq(1)
    end

    it '[disp16] direct (mod=0, rm=6)' do
      result = calc_ea(mod: 0, rm: 6, addr32: false, disp: 0x5678, seg_base: 0x3000)
      expect(result[:address]).to eq(0x3000 + 0x5678)
      expect(result[:use_ss]).to eq(0)
    end

    it '[BX] (mod=0, rm=7)' do
      result = calc_ea(mod: 0, rm: 7, addr32: false, ebx: 0x300, seg_base: 0)
      expect(result[:address]).to eq(0x300)
    end

    it '[BX+SI+disp8] (mod=1, rm=0) sign-extended' do
      result = calc_ea(mod: 1, rm: 0, addr32: false, ebx: 0x100, esi: 0x200, disp: 0x10, seg_base: 0)
      expect(result[:address]).to eq(0x310)
    end

    it '[BP+disp8] uses SS (mod=1, rm=6)' do
      result = calc_ea(mod: 1, rm: 6, addr32: false, ebp: 0x500, disp: 0x20, seg_base: 0x1000)
      expect(result[:address]).to eq(0x1000 + 0x520)
      expect(result[:use_ss]).to eq(1)
    end

    it '[BX+disp16] (mod=2, rm=7)' do
      result = calc_ea(mod: 2, rm: 7, addr32: false, ebx: 0x100, disp: 0x1234, seg_base: 0)
      expect(result[:address]).to eq(0x1334)
    end

    it 'mod=3 is register (not memory)' do
      result = calc_ea(mod: 3, rm: 0, addr32: false)
      expect(result[:is_memory]).to eq(0)
    end
  end

  context '32-bit addressing' do
    it '[EAX] (mod=0, rm=0)' do
      result = calc_ea(mod: 0, rm: 0, addr32: true, eax: 0x1000, seg_base: 0)
      expect(result[:is_memory]).to eq(1)
      expect(result[:address]).to eq(0x1000)
    end

    it '[disp32] (mod=0, rm=5)' do
      result = calc_ea(mod: 0, rm: 5, addr32: true, disp: 0xDEAD_0000, seg_base: 0)
      expect(result[:address]).to eq(0xDEAD_0000)
    end

    it '[EBP+disp8] uses SS (mod=1, rm=5)' do
      result = calc_ea(mod: 1, rm: 5, addr32: true, ebp: 0x2000, disp: 0x40, seg_base: 0x5000)
      expect(result[:address]).to eq(0x5000 + 0x2040)
      expect(result[:use_ss]).to eq(1)
    end

    it '[ECX+disp32] (mod=2, rm=1)' do
      result = calc_ea(mod: 2, rm: 1, addr32: true, ecx: 0x3000, disp: 0x100, seg_base: 0)
      expect(result[:address]).to eq(0x3100)
    end

    it 'SIB [EBX+ECX*4] (mod=0, rm=4, sib)' do
      # SIB: scale=2 (x4), index=1 (ECX), base=3 (EBX)
      sib = (2 << 6) | (1 << 3) | 3
      result = calc_ea(mod: 0, rm: 4, addr32: true, sib: sib, ebx: 0x100, ecx: 0x20, seg_base: 0)
      expect(result[:address]).to eq(0x100 + 0x20 * 4)
    end

    it 'SIB [ECX*2+disp32] (mod=0, rm=4, sib base=5)' do
      # SIB: scale=1 (x2), index=1 (ECX), base=5 (disp32 when mod=0)
      sib = (1 << 6) | (1 << 3) | 5
      result = calc_ea(mod: 0, rm: 4, addr32: true, sib: sib, ecx: 0x50, disp: 0x8000, seg_base: 0)
      expect(result[:address]).to eq(0x50 * 2 + 0x8000)
    end

    it 'SIB no index (index=4 means no index)' do
      # SIB: scale=0, index=4 (no index), base=3 (EBX)
      sib = (0 << 6) | (4 << 3) | 3
      result = calc_ea(mod: 0, rm: 4, addr32: true, sib: sib, ebx: 0x400, seg_base: 0)
      expect(result[:address]).to eq(0x400)
    end

    it 'mod=3 is register (not memory)' do
      result = calc_ea(mod: 3, rm: 2, addr32: true)
      expect(result[:is_memory]).to eq(0)
    end
  end
end
