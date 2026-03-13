# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../examples/sparc64/utilities/runners/verilator_runner'

RSpec.describe RHDL::Examples::SPARC64::VerilogRunner do
  tagged_mailbox_addr =
    RHDL::Examples::SPARC64::Integration::MAILBOX_STATUS |
    (1 << RHDL::Examples::SPARC64::Integration::REQUESTER_TAG_SHIFT)

  let(:adapter) do
    Class.new do
      define_method(:initialize) do |tagged_addr|
        @tagged_addr = tagged_addr
        @memory = Hash.new(0)
        @loaded = nil
      end

      attr_reader :loaded

      def simulator_type
        :hdl_verilator
      end

      def reset!
        true
      end

      def run_cycles(n)
        n
      end

      def load_images(boot_image:, program_image:)
        @loaded = [boot_image, program_image]
      end

      def read_memory(addr, length)
        Array.new(length) { |index| @memory[addr + index] || 0 }
      end

      def write_memory(addr, bytes)
        Array(bytes).each_with_index { |byte, index| @memory[addr + index] = byte & 0xFF }
      end

      def mailbox_status
        0
      end

      def mailbox_value
        0
      end

      def wishbone_trace
        [
          {
            cycle: 7,
            op: :write,
            addr: @tagged_addr,
            sel: 0x0F,
            write_data: 0xA0,
            read_data: nil
          }
        ]
      end

      def unmapped_accesses
        []
      end

      def debug_snapshot
        { reset: { cycle_counter: 12 }, bridge: { state: 7 } }
      end
    end.new(tagged_mailbox_addr)
  end

  it 'delegates load and run methods to the adapter' do
    runner = described_class.new(adapter: adapter)
    runner.load_images(boot_image: [0xAA], program_image: [0xBB, 0xCC])

    expect(adapter.loaded).to eq([[0xAA], [0xBB, 0xCC]])
    expect(runner.run_cycles(12)).to eq(12)
    expect(runner.clock_count).to eq(12)
    expect(runner.simulator_type).to eq(:hdl_verilator)
    expect(runner.backend).to eq(:verilator)
    expect(runner.wishbone_trace).to eq(
      [
        RHDL::Examples::SPARC64::Integration::WishboneEvent.new(
          cycle: 7,
          op: :write,
          addr: RHDL::Examples::SPARC64::Integration::MAILBOX_STATUS,
          sel: 0x0F,
          write_data: 0xA0,
          read_data: nil
        )
      ]
    )

    result = runner.run_until_complete(max_cycles: 12, batch_cycles: 6)
    expect(result[:cycles]).to eq(12)
    expect(result[:boot_handoff_seen]).to be(false)
    expect(result[:secondary_core_parked]).to be(true)
    expect(runner.debug_snapshot).to eq(reset: { cycle_counter: 12 }, bridge: { state: 7 })
  end

  it 'accepts an adapter factory without requiring the concrete default path' do
    runner = described_class.new(adapter_factory: -> { adapter })

    expect(runner.simulator_type).to eq(:hdl_verilator)
    expect(runner.backend).to eq(:verilator)
  end

  it 'aliases VerilatorRunner to VerilogRunner' do
    expect(RHDL::Examples::SPARC64::VerilatorRunner).to eq(described_class)
  end
end
