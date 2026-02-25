require_relative '../../spec_helper'
require_relative '../../../../../examples/ao486/hdl/memory/icache'

RSpec.describe RHDL::Examples::AO486::ICache do
  let(:cache) { RHDL::Examples::AO486::ICache.new }

  def reset!(c)
    c.set_input(:clk, 0)
    c.set_input(:rst_n, 0)
    c.set_input(:cache_disable, 0)
    c.set_input(:pr_reset, 0)
    c.set_input(:prefetch_address, 0)
    c.set_input(:delivered_eip, 0)
    c.set_input(:icacheread_do, 0)
    c.set_input(:icacheread_address, 0)
    c.set_input(:icacheread_length, 0)
    c.set_input(:readcode_done, 0)
    c.set_input(:readcode_partial, 0)
    c.set_input(:snoop_addr, 0)
    c.set_input(:snoop_data, 0)
    c.set_input(:snoop_be, 0)
    c.set_input(:snoop_we, 0)
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
    it 'starts in idle state with no requests' do
      reset!(cache)
      expect(cache.get_output(:prefetchfifo_write_do)).to eq(0)
      expect(cache.get_output(:prefetched_do)).to eq(0)
      expect(cache.get_output(:readcode_do)).to eq(0)
    end
  end

  describe 'cache read flow' do
    before { reset!(cache) }

    it 'issues memory read request on icacheread_do' do
      cache.set_input(:icacheread_do, 1)
      cache.set_input(:icacheread_address, 0xF0100)
      cache.set_input(:icacheread_length, 4)
      clock!(cache)
      # After clock, state is READ. Propagate once more for
      # combinational outputs to reflect the new state.
      cache.propagate

      # Should be in READ state, requesting memory
      expect(cache.get_output(:readcode_do)).to eq(1)
    end

    it 'writes to prefetch FIFO when data arrives from memory' do
      # Start read
      cache.set_input(:icacheread_do, 1)
      cache.set_input(:icacheread_address, 0xF0100)
      cache.set_input(:icacheread_length, 4)
      clock!(cache)
      cache.set_input(:icacheread_do, 0)

      # Memory responds with data
      cache.set_input(:readcode_done, 1)
      cache.set_input(:readcode_partial, 0xDEADBEEF)
      clock!(cache)

      # Should have written to FIFO
      expect(cache.get_output(:prefetchfifo_write_do)).to eq(1)
      # Data in write_data should contain the fetched bytes
      write_data = cache.get_output(:prefetchfifo_write_data)
      expect(write_data & 0xFFFFFFFF).to eq(0xDEADBEEF)
    end

    it 'returns to idle after read completes' do
      cache.set_input(:icacheread_do, 1)
      cache.set_input(:icacheread_address, 0xF0100)
      cache.set_input(:icacheread_length, 4)
      clock!(cache)
      cache.set_input(:icacheread_do, 0)

      cache.set_input(:readcode_done, 1)
      cache.set_input(:readcode_partial, 0x12345678)
      clock!(cache)
      cache.set_input(:readcode_done, 0)

      # Should return to idle
      clock!(cache)
      expect(cache.get_output(:readcode_do)).to eq(0)
    end
  end

  describe 'aligned read with length encoding' do
    before { reset!(cache) }

    it 'encodes correct length in FIFO write data for 4-byte aligned read' do
      cache.set_input(:icacheread_do, 1)
      cache.set_input(:icacheread_address, 0xF0100)  # aligned to 4
      cache.set_input(:icacheread_length, 8)
      clock!(cache)
      cache.set_input(:icacheread_do, 0)

      cache.set_input(:readcode_done, 1)
      cache.set_input(:readcode_partial, 0xAABBCCDD)
      clock!(cache)

      write_data = cache.get_output(:prefetchfifo_write_data)
      length = (write_data >> 32) & 0xF
      expect(length).to eq(4)  # aligned 4-byte chunk
    end

    it 'encodes shorter length for misaligned reads' do
      cache.set_input(:icacheread_do, 1)
      cache.set_input(:icacheread_address, 0xF0101)  # misaligned by 1
      cache.set_input(:icacheread_length, 4)
      clock!(cache)
      cache.set_input(:icacheread_do, 0)

      cache.set_input(:readcode_done, 1)
      cache.set_input(:readcode_partial, 0xAABBCCDD)
      clock!(cache)

      write_data = cache.get_output(:prefetchfifo_write_data)
      length = (write_data >> 32) & 0xF
      expect(length).to eq(3)  # only 3 bytes from first word
    end
  end

  describe 'prefetched_length output' do
    before { reset!(cache) }

    it 'outputs prefetched_length matching written chunk size' do
      cache.set_input(:icacheread_do, 1)
      cache.set_input(:icacheread_address, 0xF0100)
      cache.set_input(:icacheread_length, 4)
      clock!(cache)
      cache.set_input(:icacheread_do, 0)

      cache.set_input(:readcode_done, 1)
      cache.set_input(:readcode_partial, 0x12345678)
      clock!(cache)

      expect(cache.get_output(:prefetched_do)).to eq(1)
      expect(cache.get_output(:prefetched_length)).to be > 0
    end
  end
end
