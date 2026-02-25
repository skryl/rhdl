require_relative '../../spec_helper'
require_relative '../../../../../examples/ao486/hdl/memory/prefetch_fifo'

RSpec.describe RHDL::Examples::AO486::PrefetchFifo do
  C = RHDL::Examples::AO486::Constants
  let(:fifo) { RHDL::Examples::AO486::PrefetchFifo.new }

  def reset!(f)
    f.set_input(:clk, 0)
    f.set_input(:rst_n, 0)
    f.set_input(:pr_reset, 0)
    f.set_input(:prefetchfifo_signal_limit_do, 0)
    f.set_input(:prefetchfifo_signal_pf_do, 0)
    f.set_input(:prefetchfifo_write_do, 0)
    f.set_input(:prefetchfifo_write_data, 0)
    f.set_input(:prefetchfifo_accept_do, 0)
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

  def clear_inputs!(f)
    f.set_input(:prefetchfifo_signal_limit_do, 0)
    f.set_input(:prefetchfifo_signal_pf_do, 0)
    f.set_input(:prefetchfifo_write_do, 0)
    f.set_input(:prefetchfifo_write_data, 0)
    f.set_input(:prefetchfifo_accept_do, 0)
  end

  describe 'reset state' do
    it 'starts empty after reset' do
      reset!(fifo)
      expect(fifo.get_output(:prefetchfifo_accept_empty)).to eq(1)
      expect(fifo.get_output(:prefetchfifo_used)).to eq(0)
    end
  end

  describe 'write and read' do
    before { reset!(fifo) }

    it 'bypasses data when writing to empty FIFO' do
      # Write {length=4, data=0xDEADBEEF} to empty FIFO
      fifo.set_input(:prefetchfifo_write_do, 1)
      fifo.set_input(:prefetchfifo_write_data, (4 << 32) | 0xDEADBEEF)
      fifo.propagate  # combinational bypass - no clock needed
      # Should immediately appear on output: {4, 0, 0xDEADBEEF}
      data = fifo.get_output(:prefetchfifo_accept_data)
      expect((data >> 64) & 0xF).to eq(4)        # length nibble
      expect(data & 0xFFFFFFFF).to eq(0xDEADBEEF) # instruction data
      expect(fifo.get_output(:prefetchfifo_accept_empty)).to eq(0)
    end

    it 'stores data in FIFO and reads it back' do
      # Write entry
      fifo.set_input(:prefetchfifo_write_do, 1)
      fifo.set_input(:prefetchfifo_write_data, (3 << 32) | 0xAABBCCDD)
      clock!(fifo)
      clear_inputs!(fifo)

      # Read entry
      fifo.set_input(:prefetchfifo_accept_do, 1)
      fifo.propagate
      data = fifo.get_output(:prefetchfifo_accept_data)
      expect((data >> 64) & 0xF).to eq(3)
      expect(data & 0xFFFFFFFF).to eq(0xAABBCCDD)
    end

    it 'tracks used count' do
      # Write 3 entries
      3.times do |i|
        fifo.set_input(:prefetchfifo_write_do, 1)
        fifo.set_input(:prefetchfifo_write_data, ((i + 1) << 32) | (0x1000 * (i + 1)))
        clock!(fifo)
        clear_inputs!(fifo)
      end
      expect(fifo.get_output(:prefetchfifo_used) & 0xF).to eq(3)
    end
  end

  describe 'fault injection' do
    before { reset!(fifo) }

    it 'injects GP fault signal into FIFO' do
      fifo.set_input(:prefetchfifo_signal_limit_do, 1)
      clock!(fifo)
      clear_inputs!(fifo)
      fifo.propagate

      data = fifo.get_output(:prefetchfifo_accept_data)
      expect((data >> 64) & 0xF).to eq(C::PREFETCH_GP_FAULT)
    end

    it 'injects PF fault signal into FIFO' do
      fifo.set_input(:prefetchfifo_signal_pf_do, 1)
      clock!(fifo)
      clear_inputs!(fifo)
      fifo.propagate

      data = fifo.get_output(:prefetchfifo_accept_data)
      expect((data >> 64) & 0xF).to eq(C::PREFETCH_PF_FAULT)
    end
  end

  describe 'synchronous reset' do
    before { reset!(fifo) }

    it 'clears FIFO on pr_reset' do
      # Fill some entries
      2.times do |i|
        fifo.set_input(:prefetchfifo_write_do, 1)
        fifo.set_input(:prefetchfifo_write_data, (4 << 32) | (0x1111 * (i + 1)))
        clock!(fifo)
        clear_inputs!(fifo)
      end
      expect(fifo.get_output(:prefetchfifo_used) & 0xF).to be > 0

      # Assert pr_reset
      fifo.set_input(:pr_reset, 1)
      clock!(fifo)
      fifo.set_input(:pr_reset, 0)

      expect(fifo.get_output(:prefetchfifo_accept_empty)).to eq(1)
    end
  end
end
