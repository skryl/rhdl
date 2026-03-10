# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../examples/sparc64/utilities/runners/ir_runner'
require_relative '../../../../examples/sparc64/utilities/integration/import_loader'

RSpec.describe RHDL::Examples::SPARC64::IrRunner do
  tagged_program_addr =
    RHDL::Examples::SPARC64::Integration::PROGRAM_BASE |
    (1 << RHDL::Examples::SPARC64::Integration::REQUESTER_TAG_SHIFT)

  let(:sim) do
    Class.new do
      attr_reader :rom_loads, :memory_loads, :memory_writes

      def initialize
        @memory = Hash.new(0)
        @runner_kind = :sparc64
        @clock = 0
        @rom_loads = []
        @memory_loads = []
        @memory_writes = []
      end

      def native?
        true
      end

      def simulator_type
        :ir_compile
      end

      def runner_kind
        @runner_kind
      end

      def reset
        @clock = 0
      end

      def runner_run_cycles(n)
        @clock += n
        { cycles_run: n }
      end

      def runner_load_rom(data, offset)
        bytes = data.is_a?(String) ? data.bytes : Array(data)
        @rom_loads << [offset, bytes]
        true
      end

      def runner_load_memory(data, offset, _is_rom)
        bytes = data.is_a?(String) ? data.bytes : Array(data)
        bytes.each_with_index { |byte, index| @memory[offset + index] = byte & 0xFF }
        @memory_loads << [offset, bytes]
        true
      end

      def runner_read_memory(offset, length, mapped:)
        raise "expected unmapped=false, got #{mapped.inspect}" unless mapped == false

        Array.new(length) { |index| @memory[offset + index] || 0 }
      end

      def runner_write_memory(offset, data, mapped:)
        raise "expected unmapped=false, got #{mapped.inspect}" unless mapped == false

        bytes = data.is_a?(String) ? data.bytes : Array(data)
        bytes.each_with_index { |byte, index| @memory[offset + index] = byte & 0xFF }
        @memory_writes << [offset, bytes]
        bytes.length
      end
    end.new
  end

  def encode_u64_be(value)
    8.times.map do |index|
      shift = (7 - index) * 8
      (value >> shift) & 0xFF
    end
  end

  it 'loads boot and program images through the native memory ABI' do
    runner = described_class.new(
      component_class: double('component'),
      sim_factory: -> { sim }
    )

    runner.load_images(boot_image: [0xAA, 0xBB], program_image: [0x11, 0x22, 0x33])

    expect(sim.rom_loads).to eq([[RHDL::Examples::SPARC64::Integration::FLASH_BOOT_BASE, [0xAA, 0xBB]]])
    expect(sim.memory_loads).to eq([[RHDL::Examples::SPARC64::Integration::PROGRAM_BASE, [0x11, 0x22, 0x33]]])
  end

  it 'decodes mailbox values as big-endian 64-bit words' do
    runner = described_class.new(
      component_class: double('component'),
      sim_factory: -> { sim }
    )

    sim.runner_write_memory(
      RHDL::Examples::SPARC64::Integration::MAILBOX_STATUS,
      encode_u64_be(1),
      mapped: false
    )
    sim.runner_write_memory(
      RHDL::Examples::SPARC64::Integration::MAILBOX_VALUE,
      encode_u64_be(0xA0),
      mapped: false
    )

    expect(runner.mailbox_status).to eq(1)
    expect(runner.mailbox_value).to eq(0xA0)
  end

  it 'runs until mailbox completion' do
    trace_reader = lambda do |_sim|
      [
        {
          cycle: 12,
          op: :read,
          addr: tagged_program_addr,
          sel: 0xFF,
          write_data: nil,
          read_data: 0xAA
        }
      ]
    end
    fault_reader = ->(_sim) { [] }
    runner = described_class.new(
      component_class: double('component'),
      sim_factory: -> { sim },
      trace_reader: trace_reader,
      fault_reader: fault_reader
    )

    sim.runner_write_memory(
      RHDL::Examples::SPARC64::Integration::MAILBOX_STATUS,
      encode_u64_be(1),
      mapped: false
    )
    sim.runner_write_memory(
      RHDL::Examples::SPARC64::Integration::MAILBOX_VALUE,
      encode_u64_be(0xFFF0),
      mapped: false
    )

    result = runner.run_until_complete(max_cycles: 500, batch_cycles: 100)

    expect(result[:completed]).to be(true)
    expect(result[:timeout]).to be(false)
    expect(result[:boot_handoff_seen]).to be(true)
    expect(result[:secondary_core_parked]).to be(true)
    expect(result[:mailbox_status]).to eq(1)
    expect(result[:mailbox_value]).to eq(0xFFF0)
    expect(result[:wishbone_trace]).to eq(
      [
        RHDL::Examples::SPARC64::Integration::WishboneEvent.new(
          cycle: 12,
          op: :read,
          addr: RHDL::Examples::SPARC64::Integration::PROGRAM_BASE,
          sel: 0xFF,
          write_data: nil,
          read_data: 0xAA
        )
      ]
    )
  end

  it 'requires native :sparc64 runner support by default' do
    non_sparc_sim = sim
    allow(non_sparc_sim).to receive(:runner_kind).and_return(:riscv)

    expect do
      described_class.new(
        component_class: double('component'),
        sim_factory: -> { non_sparc_sim }
      )
    end.to raise_error(RuntimeError, /requires native :sparc64 runner support/)
  end

  it 'loads the component class through the importer-managed fast-boot path when requested' do
    component_class = double('component')
    expect(RHDL::Examples::SPARC64::Integration::ImportLoader).to receive(:load_component_class).with(
      top: 'S1Top',
      import_dir: nil,
      fast_boot: true
    ).and_return(component_class)

    runner = described_class.new(
      sim_factory: -> { sim },
      fast_boot: true
    )

    expect(runner.native?).to be(true)
  end

  it 'raises a clear error when compiler-backed input exceeds the current 128-bit backend ceiling' do
    ir = RHDL::Codegen::CIRCT::IR
    wide_component_class = Class.new do
      define_singleton_method(:to_flat_circt_nodes) do
        ir::ModuleOp.new(
          name: 'wide_top',
          ports: [
            ir::Port.new(name: 'clk', direction: :in, width: 1),
            ir::Port.new(name: 'out', direction: :out, width: 1)
          ],
          nets: [ir::Net.new(name: 'store_buffer', width: 1_440)],
          regs: [],
          assigns: [
            ir::Assign.new(
              target: 'out',
              expr: ir::Literal.new(
                value: -12_544_169_174_173_475_517_113_841_528_364_703_347_048_447,
                width: 145
              )
            )
          ],
          processes: []
        )
      end
    end

    expect do
      described_class.new(component_class: wide_component_class, backend: :compile, strict_runner_kind: false)
    end.to raise_error(
      RuntimeError,
      /supports signals up to 128 bits; imported design reaches 1440 bits.*first non-zero overwide literal is 145 bits/
    )
  end
end
