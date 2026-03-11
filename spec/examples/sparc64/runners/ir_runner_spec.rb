# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen/circt/runtime_json'

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

  it 'only refreshes the wishbone trace once when polling for completion' do
    trace_calls = 0
    fault_calls = 0
    trace_reader = lambda do |_sim|
      trace_calls += 1
      []
    end
    fault_reader = lambda do |_sim|
      fault_calls += 1
      []
    end
    runner = described_class.new(
      component_class: double('component'),
      sim_factory: -> { sim },
      trace_reader: trace_reader,
      fault_reader: fault_reader
    )

    allow(sim).to receive(:runner_run_cycles).and_wrap_original do |original, n|
      result = original.call(n)
      next result unless sim.instance_variable_get(:@clock) >= 300

      sim.runner_write_memory(
        RHDL::Examples::SPARC64::Integration::MAILBOX_STATUS,
        encode_u64_be(1),
        mapped: false
      )
      sim.runner_write_memory(
        RHDL::Examples::SPARC64::Integration::MAILBOX_VALUE,
        encode_u64_be(0x1234),
        mapped: false
      )
      result
    end

    result = runner.run_until_complete(max_cycles: 500, batch_cycles: 100)

    expect(result[:completed]).to be(true)
    expect(trace_calls).to eq(1)
    expect(fault_calls).to eq(3)
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

  it 'does not pre-reject compiler-backed input that contains overwide non-zero literals in auto mode' do
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

    simulator = instance_double(
      RHDL::Sim::Native::IR::Simulator,
      native?: true,
      simulator_type: :ir_compile,
      runner_kind: :sparc64
    )
    expect(RHDL::Sim::Native::IR).to receive(:sim_json).with(instance_of(ir::ModuleOp), backend: :compile)
                                                      .and_return('{"circt_json_version":1,"modules":[{"name":"wide_top"}]}')
    expect(RHDL::Sim::Native::IR::Simulator).to receive(:new)
      .with('{"circt_json_version":1,"modules":[{"name":"wide_top"}]}', backend: :compile)
      .and_return(simulator)

    runner = described_class.new(component_class: wide_component_class, backend: :compile, strict_runner_kind: false)

    expect(runner.sim).to eq(simulator)
  end

  it 'does not pre-reject raw overwide literals that normalize into runtime-safe slices before compiler export' do
    ir = RHDL::Codegen::CIRCT::IR
    wide_literal = -12_544_169_174_173_475_517_113_841_528_364_703_347_048_447
    wide_component_class = Class.new do
      define_singleton_method(:to_flat_circt_nodes) do
        bus = ir::Signal.new(name: 'bus', width: 145)
        ir::ModuleOp.new(
          name: 'runtime_safe_wide_top',
          ports: [
            ir::Port.new(name: 'clk', direction: :in, width: 1),
            ir::Port.new(name: 'choose', direction: :in, width: 1),
            ir::Port.new(name: 'out', direction: :out, width: 1)
          ],
          nets: [ir::Net.new(name: 'bus', width: 145)],
          regs: [],
          assigns: [
            ir::Assign.new(
              target: 'bus',
              expr: ir::Mux.new(
                condition: ir::Signal.new(name: 'choose', width: 1),
                when_true: ir::Literal.new(value: wide_literal, width: 145),
                when_false: ir::Literal.new(value: 0, width: 145),
                width: 145
              )
            ),
            ir::Assign.new(
              target: 'out',
              expr: ir::Slice.new(base: bus, range: 0..0, width: 1)
            )
          ],
          processes: [],
          instances: [],
          memories: [],
          write_ports: [],
          sync_read_ports: [],
          parameters: {}
        )
      end
    end

    runtime_mod = RHDL::Codegen::CIRCT::RuntimeJSON.normalized_runtime_modules_from_input(
      wide_component_class.to_flat_circt_nodes,
      compact_exprs: true
    ).first
    scan = described_class.allocate.send(:scan_overwide_runtime_ir, runtime_mod)

    expect(scan[:literal]).to be_nil

    simulator = instance_double(
      RHDL::Sim::Native::IR::Simulator,
      native?: true,
      simulator_type: :ir_compile,
      runner_kind: :sparc64
    )
    expect(RHDL::Sim::Native::IR).to receive(:sim_json).with(instance_of(ir::ModuleOp), backend: :compile)
                                                      .and_return('{"circt_json_version":1,"modules":[{"name":"runtime_safe_wide_top"}]}')
    expect(RHDL::Sim::Native::IR::Simulator).to receive(:new)
      .with('{"circt_json_version":1,"modules":[{"name":"runtime_safe_wide_top"}]}', backend: :compile)
      .and_return(simulator)

    runner = described_class.new(component_class: wide_component_class, backend: :compile, strict_runner_kind: false)

    expect(runner.sim).to eq(simulator)
  end

  it 'does not pre-reject overwide internal state when no non-zero literal exceeds 128 bits' do
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
              expr: ir::Literal.new(value: 1, width: 1)
            )
          ],
          processes: [],
          instances: [],
          memories: [],
          write_ports: [],
          sync_read_ports: [],
          parameters: {}
        )
      end
    end

    simulator = instance_double(
      RHDL::Sim::Native::IR::Simulator,
      native?: true,
      simulator_type: :ir_compile,
      runner_kind: :sparc64
    )
    expect(RHDL::Sim::Native::IR).to receive(:sim_json).with(instance_of(RHDL::Codegen::CIRCT::IR::ModuleOp), backend: :compile)
                                                      .and_return('{"circt_json_version":1,"modules":[{"name":"wide_top"}]}')
    expect(RHDL::Sim::Native::IR::Simulator).to receive(:new)
      .with('{"circt_json_version":1,"modules":[{"name":"wide_top"}]}', backend: :compile)
      .and_return(simulator)

    runner = described_class.new(component_class: wide_component_class, backend: :compile, strict_runner_kind: false)

    expect(runner.sim).to eq(simulator)
  end

  it 'allows full rustc compiler mode to flow through for overwide plain-core runtime state' do
    ir = RHDL::Codegen::CIRCT::IR
    wide_component_class = Class.new do
      define_singleton_method(:to_flat_circt_nodes) do
        packet_reg = ir::Signal.new(name: 'packet_reg', width: 145)
        ir::ModuleOp.new(
          name: 'wide_top',
          ports: [
            ir::Port.new(name: 'clk', direction: :in, width: 1),
            ir::Port.new(name: 'load', direction: :in, width: 1),
            ir::Port.new(name: 'flag', direction: :in, width: 1),
            ir::Port.new(name: 'opcode', direction: :in, width: 4),
            ir::Port.new(name: 'tag', direction: :in, width: 12),
            ir::Port.new(name: 'payload_hi', direction: :in, width: 64),
            ir::Port.new(name: 'payload_lo', direction: :in, width: 64),
            ir::Port.new(name: 'out', direction: :out, width: 1)
          ],
          nets: [],
          regs: [ir::Reg.new(name: 'packet_reg', width: 145, reset_value: 0)],
          assigns: [
            ir::Assign.new(
              target: 'out',
              expr: ir::Slice.new(base: packet_reg, range: 144..144, width: 1)
            )
          ],
          processes: [
            ir::Process.new(
              name: 'capture_packet',
              clocked: true,
              clock: 'clk',
              statements: [
                ir::SeqAssign.new(
                  target: :packet_reg,
                  expr: ir::Mux.new(
                    condition: ir::Signal.new(name: 'load', width: 1),
                    when_true: ir::Concat.new(
                      parts: [
                        ir::Signal.new(name: 'flag', width: 1),
                        ir::Signal.new(name: 'opcode', width: 4),
                        ir::Signal.new(name: 'tag', width: 12),
                        ir::Signal.new(name: 'payload_hi', width: 64),
                        ir::Signal.new(name: 'payload_lo', width: 64)
                      ],
                      width: 145
                    ),
                    when_false: packet_reg,
                    width: 145
                  )
                )
              ]
            )
          ],
          instances: [],
          memories: [],
          write_ports: [],
          sync_read_ports: [],
          parameters: {}
        )
      end
    end

    simulator = instance_double(
      RHDL::Sim::Native::IR::Simulator,
      native?: true,
      simulator_type: :ir_compile,
      runner_kind: :sparc64
    )
    previous = ENV['RHDL_IR_COMPILER_FORCE_RUSTC']
    ENV.delete('RHDL_IR_COMPILER_FORCE_RUSTC')

    expect(RHDL::Sim::Native::IR).to receive(:sim_json)
      .with(instance_of(RHDL::Codegen::CIRCT::IR::ModuleOp), backend: :compile)
      .and_return('{"circt_json_version":1,"modules":[{"name":"wide_top"}]}')
    expect(RHDL::Sim::Native::IR::Simulator).to receive(:new) do |json, backend:|
      expect(json).to eq('{"circt_json_version":1,"modules":[{"name":"wide_top"}]}')
      expect(backend).to eq(:compile)
      expect(ENV['RHDL_IR_COMPILER_FORCE_RUSTC']).to eq('1')
      simulator
    end

    runner = described_class.new(
      component_class: wide_component_class,
      backend: :compile,
      strict_runner_kind: false,
      compiler_mode: :rustc
    )

    expect(runner.sim).to eq(simulator)
    expect(ENV['RHDL_IR_COMPILER_FORCE_RUSTC']).to eq(previous)
  ensure
    if previous.nil?
      ENV.delete('RHDL_IR_COMPILER_FORCE_RUSTC')
    else
      ENV['RHDL_IR_COMPILER_FORCE_RUSTC'] = previous
    end
  end

  it 'can force the compiler backend down the full rustc path when requested' do
    component_class = Class.new do
      define_singleton_method(:to_flat_circt_nodes) do
        RHDL::Codegen::CIRCT::IR::ModuleOp.new(
          name: 'tiny_top',
          ports: [
            RHDL::Codegen::CIRCT::IR::Port.new(name: 'clk', direction: :in, width: 1),
            RHDL::Codegen::CIRCT::IR::Port.new(name: 'out', direction: :out, width: 1)
          ],
          nets: [],
          regs: [],
          assigns: [
            RHDL::Codegen::CIRCT::IR::Assign.new(
              target: 'out',
              expr: RHDL::Codegen::CIRCT::IR::Literal.new(value: 1, width: 1)
            )
          ],
          processes: [],
          instances: [],
          memories: [],
          write_ports: [],
          sync_read_ports: [],
          parameters: {}
        )
      end
    end

    simulator = instance_double(
      RHDL::Sim::Native::IR::Simulator,
      native?: true,
      simulator_type: :ir_compile,
      runner_kind: :sparc64
    )
    previous = ENV['RHDL_IR_COMPILER_FORCE_RUSTC']
    ENV.delete('RHDL_IR_COMPILER_FORCE_RUSTC')

    expect(RHDL::Sim::Native::IR).to receive(:sim_json).and_return('{"circt_json_version":1,"modules":[{"name":"tiny_top"}]}')
    expect(RHDL::Sim::Native::IR::Simulator).to receive(:new) do |json, backend:|
      expect(json).to eq('{"circt_json_version":1,"modules":[{"name":"tiny_top"}]}')
      expect(backend).to eq(:compile)
      expect(ENV['RHDL_IR_COMPILER_FORCE_RUSTC']).to eq('1')
      simulator
    end

    runner = described_class.new(
      component_class: component_class,
      backend: :compile,
      strict_runner_kind: false,
      compiler_mode: :rustc
    )

    expect(runner.sim).to eq(simulator)
    expect(ENV['RHDL_IR_COMPILER_FORCE_RUSTC']).to eq(previous)
  ensure
    if previous.nil?
      ENV.delete('RHDL_IR_COMPILER_FORCE_RUSTC')
    else
      ENV['RHDL_IR_COMPILER_FORCE_RUSTC'] = previous
    end
  end
end
