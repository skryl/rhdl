# frozen_string_literal: true

require 'digest'
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
        @signals = {}
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

      def has_signal?(name)
        @signals.key?(name.to_s)
      end

      def peek(name)
        @signals.fetch(name.to_s, 0)
      end

      def set_signal(name, value)
        @signals[name.to_s] = value
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
    expect(sim.memory_loads).to eq(
      [
        [0, [0xAA, 0xBB]],
        [RHDL::Examples::SPARC64::Integration::BOOT_PROM_ALIAS_BASE, [0xAA, 0xBB]],
        [RHDL::Examples::SPARC64::Integration::PROGRAM_BASE, [0x11, 0x22, 0x33]]
      ]
    )
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

  it 'captures a structured debug snapshot from the underlying simulator' do
    sim.set_signal('os2wb_inst__state', 7)
    sim.set_signal('os2wb_inst__wb_cycle', 1)
    sim.set_signal('os2wb_inst__wb_addr', 0x1000)
    sim.set_signal('sparc_0__ifu__errdp__fdp_erb_pc_f', 0x2000)
    sim.set_signal('sparc_0__tlu__misctl__ifu_npc_w', 0x2004)
    sim.set_signal('sparc_0__ifu__swl__thrfsm0__thr_state', 3)
    sim.set_signal('sparc_1__ifu__swl__thrfsm0__thr_state', 4)
    sim.set_signal('sparc_0__ifu__ifqctl__lsu_ifu_pcxpkt_ack_d', 1)
    sim.set_signal('sparc_0__ifu__ifqctl__ifu_lsu_pcxreq_d', 0)
    sim.set_signal('sparc_0__exu__irf__bw_r_irf_core__old_agp_d1', 2)
    sim.set_signal('sparc_0__exu__irf__bw_r_irf_core__new_agp_d2', 5)
    sim.set_signal('sparc_0__exu__irf__bw_r_irf_core__register02__wrens', 0xA)
    sim.set_signal('sparc_0__exu__irf__bw_r_irf_core__register02__rd_thread', 1)
    sim.set_signal('sparc_0__exu__irf__bw_r_irf_core__register02__save', 1)
    sim.set_signal('sparc_0__exu__irf__bw_r_irf_core__register02__wr_data', 0x1234)

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
      encode_u64_be(0x55AA),
      mapped: false
    )

    runner.run_cycles(12)

    expect(runner.debug_snapshot).to include(
      reset: {
        cycle_counter: 12,
        mailbox_status: 1,
        mailbox_value: 0x55AA
      },
      bridge: include(
        state: 7,
        wb_cycle: true,
        wb_addr: 0x1000
      ),
      thread0: include(
        fetch_pc_f: 0x2000,
        npc_w: 0x2004,
        thread_states: [3]
      ),
      thread1: include(
        thread_states: [4]
      ),
      ifq: include(
        lsu_ifu_pcxpkt_ack_d: true,
        ifu_lsu_pcxreq_d: false
      ),
      irf: include(
        old_agp: 2,
        new_agp: 5,
        register02: include(
          wrens: 0xA,
          rd_thread: 1,
          save: true,
          wr_data: 0x1234
        )
      )
    )
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

  it 'rejects removed auto/runtime-only compiler modes for SPARC64' do
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
          assigns: [],
          processes: [],
          instances: [],
          memories: [],
          write_ports: [],
          sync_read_ports: [],
          parameters: {}
        )
      end
    end

    expect do
      described_class.new(
        component_class: component_class,
        backend: :compile,
        strict_runner_kind: false,
        compiler_mode: :auto
      )
    end.to raise_error(ArgumentError, /rustc-only/)

    expect do
      described_class.new(
        component_class: component_class,
        backend: :compile,
        strict_runner_kind: false,
        compiler_mode: :runtime_only
      )
    end.to raise_error(ArgumentError, /rustc-only/)
  end

  it 'always forces the compiler backend down the rustc path' do
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

  it 'uses a cached runtime JSON artifact from the import report when available' do
    simulator = instance_double(
      RHDL::Sim::Native::IR::Simulator,
      native?: true,
      simulator_type: :ir_compile,
      runner_kind: :sparc64
    )
    component_class = Class.new do
      define_singleton_method(:verilog_module_name) { 's1_top' }
    end
    signature = Digest::SHA256.hexdigest([
      Digest::SHA256.file(File.expand_path('../../../../lib/rhdl/codegen/circt/runtime_json.rb', __dir__)).hexdigest,
      'compact_exprs=true'
    ].join("\n"))

    Dir.mktmpdir('sparc64_ir_runner_cache') do |dir|
      runtime_json_path = File.join(dir, '.mixed_import', 's1_top.runtime.json')
      FileUtils.mkdir_p(File.dirname(runtime_json_path))
      File.write(runtime_json_path, '{"circt_json_version":1,"modules":[{"name":"s1_top"}]}')
      File.write(
        File.join(dir, 'import_report.json'),
        JSON.pretty_generate(
          'artifacts' => {
            'runtime_json_path' => runtime_json_path,
            'runtime_json_export_signature' => signature
          }
        )
      )

      expect(RHDL::Sim::Native::IR).not_to receive(:sim_json)
      expect(RHDL::Sim::Native::IR::Simulator).to receive(:new)
        .with('{"circt_json_version":1,"modules":[{"name":"s1_top"}]}', backend: :compile)
        .and_return(simulator)

      runner = described_class.new(
        component_class: component_class,
        import_dir: dir,
        backend: :compile,
        strict_runner_kind: false
      )

      expect(runner.sim).to eq(simulator)
      expect(runner.import_dir).to eq(File.expand_path(dir))
    end
  end

  it 'uses importer-produced runtime JSON artifacts even when the report has no serializer signature' do
    simulator = instance_double(
      RHDL::Sim::Native::IR::Simulator,
      native?: true,
      simulator_type: :ir_compile,
      runner_kind: :sparc64
    )
    component_class = Class.new do
      define_singleton_method(:verilog_module_name) { 's1_top' }
    end

    Dir.mktmpdir('sparc64_ir_runner_import_runtime') do |dir|
      runtime_json_path = File.join(dir, 's1_top.runtime.json')
      File.write(runtime_json_path, '{"circt_json_version":1,"modules":[{"name":"imported"}]}')
      File.write(
        File.join(dir, 'import_report.json'),
        JSON.pretty_generate(
          'artifacts' => {
            'runtime_json_path' => runtime_json_path
          }
        )
      )

      expect(RHDL::Codegen::CIRCT::RuntimeJSON).not_to receive(:dump_to_io)
      expect(RHDL::Sim::Native::IR::Simulator).to receive(:new)
        .with('{"circt_json_version":1,"modules":[{"name":"imported"}]}', backend: :compile)
        .and_return(simulator)

      runner = described_class.new(
        component_class: component_class,
        import_dir: dir,
        backend: :compile,
        strict_runner_kind: false
      )

      expect(runner.sim).to eq(simulator)
    end
  end

  it 'regenerates cached runtime JSON when the import report lacks the current export signature' do
    simulator = instance_double(
      RHDL::Sim::Native::IR::Simulator,
      native?: true,
      simulator_type: :ir_compile,
      runner_kind: :sparc64
    )
    runtime_nodes = instance_double(RHDL::Codegen::CIRCT::IR::ModuleOp)
    component_class = Class.new do
      define_singleton_method(:verilog_module_name) { 's1_top' }
    end
    component_class.define_singleton_method(:to_flat_circt_nodes) { runtime_nodes }

    Dir.mktmpdir('sparc64_ir_runner_cache_stale') do |dir|
      runtime_json_path = File.join(dir, '.mixed_import', 's1_top.runtime.json')
      FileUtils.mkdir_p(File.dirname(runtime_json_path))
      File.write(runtime_json_path, '{"circt_json_version":1,"modules":[{"name":"stale"}]}')
      report_path = File.join(dir, 'import_report.json')
      File.write(
        report_path,
        JSON.pretty_generate(
          'artifacts' => {
            'runtime_json_path' => runtime_json_path,
            'runtime_json_export_signature' => 'stale-signature'
          }
        )
      )

      expect(RHDL::Codegen::CIRCT::RuntimeJSON).to receive(:dump_to_io)
        .with(runtime_nodes, instance_of(File), compact_exprs: true) do |_nodes, io, compact_exprs:|
          expect(compact_exprs).to eq(true)
          io.write('{"circt_json_version":1,"modules":[{"name":"fresh"}]}')
        end
      expect(RHDL::Sim::Native::IR::Simulator).to receive(:new)
        .with('{"circt_json_version":1,"modules":[{"name":"fresh"}]}', backend: :compile)
        .and_return(simulator)

      runner = described_class.new(
        component_class: component_class,
        import_dir: dir,
        backend: :compile,
        strict_runner_kind: false
      )

      expect(runner.sim).to eq(simulator)
      report = JSON.parse(File.read(report_path))
      expect(report.dig('artifacts', 'runtime_json_path')).to eq(runtime_json_path)
      expect(report.dig('artifacts', 'runtime_json_export_signature')).to be_a(String)
      expect(File.read(runtime_json_path)).to eq('{"circt_json_version":1,"modules":[{"name":"fresh"}]}')
    end
  end
end
