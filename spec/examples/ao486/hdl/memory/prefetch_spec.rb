require_relative '../../spec_helper'
require_relative '../../../../../examples/ao486/hdl/memory/prefetch'

RSpec.describe RHDL::Examples::AO486::Prefetch do
  C = RHDL::Examples::AO486::Constants
  let(:pf) { RHDL::Examples::AO486::Prefetch.new }

  def reset!(f)
    f.set_input(:clk, 0)
    f.set_input(:rst_n, 0)
    f.set_input(:pr_reset, 0)
    f.set_input(:reset_prefetch, 0)
    f.set_input(:prefetch_cpl, 0)
    f.set_input(:prefetch_eip, 0)
    f.set_input(:cs_cache, 0)
    f.set_input(:prefetched_do, 0)
    f.set_input(:prefetched_length, 0)
    f.set_input(:prefetched_accept_do, 0)
    f.set_input(:prefetched_accept_length, 0)
    f.propagate
    f.set_input(:clk, 1)
    f.propagate
    f.set_input(:rst_n, 1)
  end

  def clock!(f)
    f.set_input(:clk, 0)
    f.propagate
    f.set_input(:clk, 1)
    f.propagate
  end

  # Build a minimal CS descriptor cache:
  # base = cs_cache[63:56] | cs_cache[39:16]
  # limit = G ? {cs_cache[51:48],cs_cache[15:0],12'hFFF} : {12'd0,cs_cache[51:48],cs_cache[15:0]}
  def make_cs_cache(base:, limit:, g: 0)
    base_hi = (base >> 24) & 0xFF
    base_lo = base & 0xFFFFFF
    if g == 1
      limit_hi = (limit >> 28) & 0xF
      limit_lo = (limit >> 12) & 0xFFFF
    else
      limit_hi = (limit >> 16) & 0xF
      limit_lo = limit & 0xFFFF
    end
    desc = 0
    desc |= (base_hi << 56)
    desc |= (base_lo << 16)
    desc |= (limit_hi << 48)
    desc |= limit_lo
    desc |= (g << 55)
    desc
  end

  describe 'reset state' do
    it 'resets linear to STARTUP_PREFETCH_LINEAR' do
      reset!(pf)
      expect(pf.get_output(:prefetch_address)).to eq(C::STARTUP_PREFETCH_LINEAR)
    end

    it 'outputs prefetch_length based on startup limit' do
      reset!(pf)
      # STARTUP_PREFETCH_LIMIT = 16, so prefetch_length = min(16, 16) = 16
      expect(pf.get_output(:prefetch_length)).to eq(16)
    end
  end

  describe 'segment limit tracking' do
    before { reset!(pf) }

    it 'computes limit from cs_cache and prefetch_eip on pr_reset' do
      # CS base = 0xF0000, limit = 0xFFFF (64KB real mode segment)
      cs = make_cs_cache(base: 0xF0000, limit: 0xFFFF, g: 0)
      pf.set_input(:cs_cache, cs)
      pf.set_input(:prefetch_eip, 0xFFF0)

      pf.set_input(:pr_reset, 1)
      clock!(pf)
      pf.set_input(:pr_reset, 0)

      # limit = cs_limit - eip + 1 = 0xFFFF - 0xFFF0 + 1 = 16
      expect(pf.get_output(:prefetch_length)).to eq(16)
    end

    it 'decrements limit when prefetched_do fires' do
      cs = make_cs_cache(base: 0xF0000, limit: 0xFFFF, g: 0)
      pf.set_input(:cs_cache, cs)
      pf.set_input(:prefetch_eip, 0xFFF0)
      pf.set_input(:pr_reset, 1)
      clock!(pf)
      pf.set_input(:pr_reset, 0)

      # Simulate icache returning 4 bytes
      pf.set_input(:prefetched_do, 1)
      pf.set_input(:prefetched_length, 4)
      clock!(pf)
      pf.set_input(:prefetched_do, 0)

      # limit was 16, subtract 4 => 12
      expect(pf.get_output(:prefetch_length)).to eq(12)
    end

    it 'signals limit when limit reaches 0' do
      cs = make_cs_cache(base: 0xF0000, limit: 0xFFFF, g: 0)
      pf.set_input(:cs_cache, cs)
      pf.set_input(:prefetch_eip, 0xFFFC)
      pf.set_input(:pr_reset, 1)
      clock!(pf)
      pf.set_input(:pr_reset, 0)

      # limit = 0xFFFF - 0xFFFC + 1 = 4
      # Consume all 4 bytes
      pf.set_input(:prefetched_do, 1)
      pf.set_input(:prefetched_length, 4)
      clock!(pf)
      pf.set_input(:prefetched_do, 0)

      # limit should now be 0, signal_limit should fire
      expect(pf.get_output(:prefetchfifo_signal_limit_do)).to eq(1)
    end
  end

  describe 'linear address tracking' do
    before { reset!(pf) }

    it 'updates linear address on pr_reset to cs_base + eip' do
      cs = make_cs_cache(base: 0xF0000, limit: 0xFFFF, g: 0)
      pf.set_input(:cs_cache, cs)
      pf.set_input(:prefetch_eip, 0x100)
      pf.set_input(:pr_reset, 1)
      clock!(pf)
      pf.set_input(:pr_reset, 0)

      expect(pf.get_output(:prefetch_address)).to eq(0xF0000 + 0x100)
    end

    it 'advances linear address on prefetched_do' do
      cs = make_cs_cache(base: 0xF0000, limit: 0xFFFF, g: 0)
      pf.set_input(:cs_cache, cs)
      pf.set_input(:prefetch_eip, 0x100)
      pf.set_input(:pr_reset, 1)
      clock!(pf)
      pf.set_input(:pr_reset, 0)

      initial_addr = pf.get_output(:prefetch_address)
      pf.set_input(:prefetched_do, 1)
      pf.set_input(:prefetched_length, 4)
      clock!(pf)
      pf.set_input(:prefetched_do, 0)

      expect(pf.get_output(:prefetch_address)).to eq(initial_addr + 4)
    end
  end

  describe 'supervisor/user' do
    before { reset!(pf) }

    it 'sets prefetch_su=1 when CPL=3 (user mode)' do
      pf.set_input(:prefetch_cpl, 3)
      pf.propagate
      expect(pf.get_output(:prefetch_su)).to eq(1)
    end

    it 'sets prefetch_su=0 when CPL=0 (supervisor)' do
      pf.set_input(:prefetch_cpl, 0)
      pf.propagate
      expect(pf.get_output(:prefetch_su)).to eq(0)
    end
  end
end
