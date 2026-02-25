require_relative '../../spec_helper'
require_relative '../../../../../examples/ao486/hdl/pipeline/fetch'

RSpec.describe RHDL::Examples::AO486::Fetch do
  C = RHDL::Examples::AO486::Constants
  let(:fetch) { RHDL::Examples::AO486::Fetch.new }

  def reset!(f)
    f.set_input(:clk, 0)
    f.set_input(:rst_n, 0)
    f.set_input(:pr_reset, 0)
    f.set_input(:wr_eip, 0)
    f.set_input(:prefetchfifo_accept_data, 0)
    f.set_input(:prefetchfifo_accept_empty, 1)
    f.set_input(:dec_acceptable, 0)
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

  # Build a 68-bit FIFO accept_data: {length[67:64], padding[63:32], data[31:0]}
  def fifo_data(length, data32)
    (length << 64) | data32
  end

  describe 'reset state' do
    it 'resets fetch_count to 0 and outputs 0 fetch_valid when empty' do
      reset!(fetch)
      expect(fetch.get_output(:fetch_valid)).to eq(0)
    end
  end

  describe 'prefetch_eip passthrough' do
    it 'passes wr_eip directly to prefetch_eip' do
      reset!(fetch)
      fetch.set_input(:wr_eip, 0xFFF0)
      fetch.propagate
      expect(fetch.get_output(:prefetch_eip)).to eq(0xFFF0)
    end
  end

  describe 'instruction delivery' do
    before { reset!(fetch) }

    it 'delivers instruction bytes when FIFO not empty' do
      # Simulate FIFO providing 4 bytes: length=4, data=0x90909090 (4 NOPs)
      fetch.set_input(:prefetchfifo_accept_empty, 0)
      fetch.set_input(:prefetchfifo_accept_data, fifo_data(4, 0x90909090))
      fetch.propagate

      expect(fetch.get_output(:fetch_valid)).to eq(4)
      expect(fetch.get_output(:fetch) & 0xFFFFFFFF).to eq(0x90909090)
    end

    it 'delivers 0 fetch_valid when FIFO is empty' do
      fetch.set_input(:prefetchfifo_accept_empty, 1)
      fetch.propagate
      expect(fetch.get_output(:fetch_valid)).to eq(0)
    end
  end

  describe 'barrel shift with fetch_count' do
    before { reset!(fetch) }

    it 'shifts data right by fetch_count bytes' do
      # Provide 4-byte entry: data = 0xAABBCCDD
      fetch.set_input(:prefetchfifo_accept_empty, 0)
      fetch.set_input(:prefetchfifo_accept_data, fifo_data(4, 0xAABBCCDD))
      # Decode consumes 1 byte (partial)
      fetch.set_input(:dec_acceptable, 1)
      fetch.propagate  # combinational: sets partial=1 since 1 < 4
      clock!(fetch)    # fetch_count becomes 1

      # Now fetch_count=1, data should be shifted right by 1 byte
      fetch.set_input(:dec_acceptable, 0)
      fetch.propagate
      fetched = fetch.get_output(:fetch) & 0xFFFFFF
      expect(fetched).to eq(0xAABBCC)  # upper 3 bytes of original
      expect(fetch.get_output(:fetch_valid)).to eq(3)  # 4-1=3
    end

    it 'resets fetch_count when FIFO entry fully consumed' do
      fetch.set_input(:prefetchfifo_accept_empty, 0)
      fetch.set_input(:prefetchfifo_accept_data, fifo_data(4, 0x11223344))
      # Decode consumes all 4 bytes
      fetch.set_input(:dec_acceptable, 4)
      fetch.propagate
      expect(fetch.get_output(:prefetchfifo_accept_do)).to eq(1)
      clock!(fetch)

      # fetch_count should reset to 0 (accept_do was set)
      # Need new data now
      fetch.set_input(:prefetchfifo_accept_empty, 0)
      fetch.set_input(:prefetchfifo_accept_data, fifo_data(3, 0x55667788))
      fetch.set_input(:dec_acceptable, 0)
      fetch.propagate
      expect(fetch.get_output(:fetch_valid)).to eq(3)
    end
  end

  describe 'fault detection' do
    before { reset!(fetch) }

    it 'detects GP fault from FIFO data' do
      fetch.set_input(:prefetchfifo_accept_empty, 0)
      fetch.set_input(:prefetchfifo_accept_data, fifo_data(C::PREFETCH_GP_FAULT, 0))
      fetch.propagate

      expect(fetch.get_output(:fetch_limit)).to eq(1)
      expect(fetch.get_output(:fetch_page_fault)).to eq(0)
      expect(fetch.get_output(:fetch_valid)).to eq(0)
    end

    it 'detects page fault from FIFO data' do
      fetch.set_input(:prefetchfifo_accept_empty, 0)
      fetch.set_input(:prefetchfifo_accept_data, fifo_data(C::PREFETCH_PF_FAULT, 0))
      fetch.propagate

      expect(fetch.get_output(:fetch_page_fault)).to eq(1)
      expect(fetch.get_output(:fetch_limit)).to eq(0)
      expect(fetch.get_output(:fetch_valid)).to eq(0)
    end
  end

  describe 'FIFO accept control' do
    before { reset!(fetch) }

    it 'sets accept_do when decode consumes all available bytes' do
      fetch.set_input(:prefetchfifo_accept_empty, 0)
      fetch.set_input(:prefetchfifo_accept_data, fifo_data(3, 0x112233))
      fetch.set_input(:dec_acceptable, 4)  # can accept more than available
      fetch.propagate

      expect(fetch.get_output(:prefetchfifo_accept_do)).to eq(1)
    end

    it 'does not accept when decode consumes less than available' do
      fetch.set_input(:prefetchfifo_accept_empty, 0)
      fetch.set_input(:prefetchfifo_accept_data, fifo_data(4, 0x11223344))
      fetch.set_input(:dec_acceptable, 2)
      fetch.propagate

      expect(fetch.get_output(:prefetchfifo_accept_do)).to eq(0)
    end

    it 'does not accept fault entries' do
      fetch.set_input(:prefetchfifo_accept_empty, 0)
      fetch.set_input(:prefetchfifo_accept_data, fifo_data(C::PREFETCH_GP_FAULT, 0))
      fetch.set_input(:dec_acceptable, 15)
      fetch.propagate

      expect(fetch.get_output(:prefetchfifo_accept_do)).to eq(0)
    end
  end

  describe 'pr_reset' do
    before { reset!(fetch) }

    it 'resets fetch_count on pr_reset' do
      # Build up some fetch_count
      fetch.set_input(:prefetchfifo_accept_empty, 0)
      fetch.set_input(:prefetchfifo_accept_data, fifo_data(4, 0xDEADBEEF))
      fetch.set_input(:dec_acceptable, 2)
      fetch.propagate
      clock!(fetch)

      # Now pr_reset
      fetch.set_input(:pr_reset, 1)
      clock!(fetch)
      fetch.set_input(:pr_reset, 0)
      fetch.set_input(:prefetchfifo_accept_data, fifo_data(4, 0xCAFEBABE))
      fetch.propagate

      expect(fetch.get_output(:fetch_valid)).to eq(4)  # full 4, no offset
    end
  end
end
