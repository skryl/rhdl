require_relative '../../spec_helper'
require_relative '../../../../../examples/ao486/hdl/memory/prefetch_control'

RSpec.describe RHDL::Examples::AO486::PrefetchControl do
  let(:ctrl) { RHDL::Examples::AO486::PrefetchControl.new }

  def reset!(c)
    c.set_input(:clk, 0)
    c.set_input(:rst_n, 0)
    c.set_input(:pr_reset, 0)
    c.set_input(:prefetch_address, 0)
    c.set_input(:prefetch_length, 0)
    c.set_input(:prefetch_su, 0)
    c.set_input(:prefetchfifo_used, 0)
    c.set_input(:tlbcode_do, 0)
    c.set_input(:tlbcode_linear, 0)
    c.set_input(:tlbcode_physical, 0)
    c.set_input(:tlbcode_cache_disable, 0)
    c.propagate
    c.set_input(:clk, 1)
    c.propagate
    c.set_input(:rst_n, 1)
  end

  def clock!(c)
    c.set_input(:clk, 0)
    c.propagate
    c.set_input(:clk, 1)
    c.propagate
  end

  describe 'reset state' do
    it 'starts in TLB_REQUEST state with no requests active' do
      reset!(ctrl)
      expect(ctrl.get_output(:tlbcoderequest_do)).to eq(0)
      expect(ctrl.get_output(:icacheread_do)).to eq(0)
    end
  end

  describe 'TLB request' do
    before { reset!(ctrl) }

    it 'issues TLB request when length>0, FIFO not full, not resetting' do
      ctrl.set_input(:prefetch_address, 0xF0100)
      ctrl.set_input(:prefetch_length, 16)
      ctrl.set_input(:prefetchfifo_used, 0)  # empty FIFO
      ctrl.propagate

      expect(ctrl.get_output(:tlbcoderequest_do)).to eq(1)
      expect(ctrl.get_output(:tlbcoderequest_address)).to eq(0xF0100)
    end

    it 'suppresses TLB request when FIFO has >= 3 entries' do
      ctrl.set_input(:prefetch_address, 0xF0100)
      ctrl.set_input(:prefetch_length, 16)
      ctrl.set_input(:prefetchfifo_used, 3)
      ctrl.propagate

      expect(ctrl.get_output(:tlbcoderequest_do)).to eq(0)
    end

    it 'suppresses TLB request when prefetch_length is 0' do
      ctrl.set_input(:prefetch_address, 0xF0100)
      ctrl.set_input(:prefetch_length, 0)
      ctrl.set_input(:prefetchfifo_used, 0)
      ctrl.propagate

      expect(ctrl.get_output(:tlbcoderequest_do)).to eq(0)
    end
  end

  describe 'TLB response → icache read' do
    before { reset!(ctrl) }

    it 'transitions to ICACHE state and issues icacheread on TLB response' do
      ctrl.set_input(:prefetch_address, 0xF0100)
      ctrl.set_input(:prefetch_length, 16)
      ctrl.set_input(:prefetchfifo_used, 0)
      # Simulate TLB response
      ctrl.set_input(:tlbcode_do, 1)
      ctrl.set_input(:tlbcode_linear, 0xF0100)
      ctrl.set_input(:tlbcode_physical, 0x00F0100)
      ctrl.set_input(:tlbcode_cache_disable, 0)
      clock!(ctrl)

      # Should be in ICACHE state now and issuing reads
      expect(ctrl.get_output(:icacheread_do)).to eq(1)
      expect(ctrl.get_output(:icacheread_address)).to eq(0x00F0100)
    end
  end

  describe 'page boundary awareness' do
    before { reset!(ctrl) }

    it 'limits length to bytes remaining in current page' do
      # Address 0xFF0 means 0x1000 - 0xFF0 = 16 bytes left in page
      ctrl.set_input(:prefetch_address, 0xF0FF0)
      ctrl.set_input(:prefetch_length, 16)
      ctrl.set_input(:prefetchfifo_used, 0)
      ctrl.set_input(:tlbcode_do, 1)
      ctrl.set_input(:tlbcode_physical, 0xF0FF0)
      ctrl.set_input(:tlbcode_linear, 0xF0FF0)
      clock!(ctrl)

      # length should be min(left_in_page=16, prefetch_length=16) = 16
      expect(ctrl.get_output(:icacheread_length)).to eq(16)
    end

    it 'clips length when near page boundary' do
      # Address 0xFFC means 4 bytes left in page
      ctrl.set_input(:prefetch_address, 0xF0FFC)
      ctrl.set_input(:prefetch_length, 16)
      ctrl.set_input(:prefetchfifo_used, 0)
      ctrl.set_input(:tlbcode_do, 1)
      ctrl.set_input(:tlbcode_physical, 0xF0FFC)
      ctrl.set_input(:tlbcode_linear, 0xF0FFC)
      clock!(ctrl)

      # left_in_page = 4096 - 0xFFC = 4, so length = min(4, 16) = 4
      expect(ctrl.get_output(:icacheread_length)).to eq(4)
    end
  end

  describe 'FIFO backpressure in ICACHE state' do
    before { reset!(ctrl) }

    it 'returns to TLB_REQUEST when FIFO >= 8' do
      # Get into ICACHE state first
      ctrl.set_input(:prefetch_address, 0xF0100)
      ctrl.set_input(:prefetch_length, 16)
      ctrl.set_input(:prefetchfifo_used, 0)
      ctrl.set_input(:tlbcode_do, 1)
      ctrl.set_input(:tlbcode_physical, 0xF0100)
      ctrl.set_input(:tlbcode_linear, 0xF0100)
      clock!(ctrl)
      ctrl.set_input(:tlbcode_do, 0)

      # Now set FIFO nearly full
      ctrl.set_input(:prefetchfifo_used, 8)
      clock!(ctrl)

      # Should have returned to TLB_REQUEST
      expect(ctrl.get_output(:icacheread_do)).to eq(0)
    end
  end
end
