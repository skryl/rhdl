# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'tmpdir'

require_relative '../../../../examples/sparc64/utilities/runners/arcilator_runner'

RSpec.describe RHDL::Examples::SPARC64::ArcilatorRunner do
  around do |example|
    Dir.mktmpdir('sparc64_arcilator_runner_spec') do |dir|
      @tmp_dir = dir
      example.run
    end
  end

  def write_import_tree(top: 's1_top', normalized: false)
    import_dir = File.join(@tmp_dir, 'import')
    FileUtils.mkdir_p(File.join(import_dir, '.mixed_import'))
    mlir_path = File.join(import_dir, '.mixed_import', "#{top}.core.mlir")
    File.write(mlir_path, "hw.module @#{top}() {\n  hw.output\n}\n")
    normalized_path = File.join(import_dir, '.mixed_import', "#{top}.normalized.core.mlir")
    File.write(normalized_path, "hw.module @#{top}() {\n  hw.output\n}\n") if normalized
    File.write(
      File.join(import_dir, 'import_report.json'),
      JSON.generate(
        success: true,
        top: top,
        artifacts: {
          core_mlir_path: mlir_path,
          normalized_core_mlir_path: (normalized ? normalized_path : nil)
        }
      )
    )
    [import_dir, mlir_path, normalized_path]
  end

  let(:mock_sim) do
    Class.new do
      attr_reader :rom_loads, :memory_loads, :memory_writes

      def initialize
        @memory = Hash.new(0)
        @rom_loads = []
        @memory_loads = []
        @memory_writes = []
      end

      def runner_supported?
        true
      end

      def runner_kind
        :sparc64
      end

      def reset
        true
      end

      def close; end

      def runner_run_cycles(n)
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
        Array.new(length) { |index| @memory[offset + index] || 0 }
      end

      def runner_write_memory(offset, data, mapped:)
        bytes = data.is_a?(String) ? data.bytes : Array(data)
        bytes.each_with_index { |byte, index| @memory[offset + index] = byte & 0xFF }
        @memory_writes << [offset, bytes]
        bytes.length
      end

      def runner_sparc64_wishbone_trace
        [
          {
            cycle: 7,
            op: :write,
            addr: RHDL::Examples::SPARC64::Integration::MAILBOX_STATUS |
                  (1 << RHDL::Examples::SPARC64::Integration::REQUESTER_TAG_SHIFT),
            sel: 0x0F,
            write_data: 0xA0,
            read_data: nil
          }
        ]
      end

      def runner_sparc64_unmapped_accesses
        []
      end
    end.new
  end

  def build_runner_with_mock_sim(sim, import_dir: nil, jit: false)
    id, = write_import_tree unless import_dir
    import_dir ||= id

    runner = described_class.new(
      import_dir: import_dir,
      build_dir: File.join(@tmp_dir, 'build'),
      compile_now: false,
      jit: jit
    )
    runner.instance_variable_set(:@sim, sim)
    runner
  end

  it 'exposes backend metadata and reports uncompiled state with compile_now: false' do
    import_dir, = write_import_tree

    runner = described_class.new(
      import_dir: import_dir,
      build_dir: File.join(@tmp_dir, 'build'),
      compile_now: false
    )

    expect(runner.backend).to eq(:arcilator)
    expect(runner.simulator_type).to eq(:hdl_arcilator)
    expect(runner.native?).to eq(true)
    expect(runner.compiled?).to eq(false)
    expect(runner.build_dir).to eq(File.join(@tmp_dir, 'build'))
  end

  it 'prefers normalized (RHDL-raised) core MLIR over raw import MLIR when both are present' do
    import_dir, _mlir_path, normalized_path = write_import_tree(normalized: true)

    runner = described_class.new(
      import_dir: import_dir,
      build_dir: File.join(@tmp_dir, 'build'),
      compile_now: false
    )

    expect(runner.instance_variable_get(:@core_mlir_path)).to eq(normalized_path)
  end

  it 'can be configured to use staged Verilog as the arcilator source artifact' do
    staged_root = File.join(@tmp_dir, 'staged')
    FileUtils.mkdir_p(staged_root)
    top_file = File.join(staged_root, 's1_top.v')
    File.write(top_file, "module s1_top;\nendmodule\n")
    staged_bundle = Struct.new(
      :build_dir,
      :staged_root,
      :top_module,
      :top_file,
      :include_dirs,
      :source_files,
      :verilator_args,
      :fast_boot,
      keyword_init: true
    ).new(
      build_dir: File.join(@tmp_dir, 'staged_bundle'),
      staged_root: staged_root,
      top_module: 's1_top',
      top_file: top_file,
      include_dirs: [staged_root],
      source_files: [],
      verilator_args: ['-I' + staged_root],
      fast_boot: true
    )

    runner = described_class.new(
      source_kind: :staged_verilog,
      source_bundle: staged_bundle,
      build_dir: File.join(@tmp_dir, 'build'),
      compile_now: false
    )

    expect(runner.source_kind).to eq(:staged_verilog)
    expect(runner.instance_variable_get(:@top_module_name)).to eq('s1_top')
    expect(runner.instance_variable_get(:@core_mlir_path)).to be_nil
  end

  it 'assigns numbered artifact paths for the staged-Verilog arcilator pipeline' do
    staged_root = File.join(@tmp_dir, 'staged')
    FileUtils.mkdir_p(staged_root)
    top_file = File.join(staged_root, 's1_top.v')
    File.write(top_file, "module s1_top;\nendmodule\n")
    staged_bundle = Struct.new(
      :build_dir,
      :staged_root,
      :top_module,
      :top_file,
      :include_dirs,
      :source_files,
      :verilator_args,
      :fast_boot,
      keyword_init: true
    ).new(
      build_dir: File.join(@tmp_dir, 'staged_bundle'),
      staged_root: staged_root,
      top_module: 's1_top',
      top_file: top_file,
      include_dirs: [staged_root],
      source_files: [],
      verilator_args: ['-I' + staged_root],
      fast_boot: true
    )

    runner = described_class.new(
      source_kind: :staged_verilog,
      source_bundle: staged_bundle,
      build_dir: File.join(@tmp_dir, 'build'),
      compile_now: false
    )

    expect(runner.send(:staged_source_mlir_path)).to eq(File.join(@tmp_dir, 'build', '01.s1_top.staged.core.mlir'))
    expect(runner.send(:arc_stage_index_offset)).to eq(1)
    expect(runner.send(:llvm_ir_path)).to eq(File.join(@tmp_dir, 'build', '10.s1_top.arc.ll'))
    expect(runner.send(:state_file_path)).to eq(File.join(@tmp_dir, 'build', '11.s1_top.state.json'))
    expect(runner.send(:wrapper_cpp_path)).to eq(File.join(@tmp_dir, 'build', '12.s1_top.std_abi_arc_wrapper.cpp'))
    expect(runner.send(:object_file_path)).to eq(File.join(@tmp_dir, 'build', '13.s1_top.arc.o'))
    expect(File.basename(runner.send(:shared_lib_path))).to match(/\A14\.libsparc64_arc_std_sim\.(?:dylib|so)\z/)
  end

  it 'requests CIRCT-safe staged hierarchy stubs when building the staged-Verilog source bundle' do
    bundle_class = Class.new do
      class << self
        attr_reader :last_kwargs
      end

      def initialize(**kwargs)
        self.class.instance_variable_set(:@last_kwargs, kwargs)
      end

      def build
        Struct.new(
          :build_dir,
          :staged_root,
          :top_module,
          :top_file,
          :include_dirs,
          :source_files,
          :verilator_args,
          :fast_boot,
          keyword_init: true
        ).new(
          build_dir: '/tmp/staged_bundle',
          staged_root: '/tmp/staged_bundle',
          top_module: 's1_top',
          top_file: '/tmp/staged_bundle/s1_top.v',
          include_dirs: [],
          source_files: [],
          verilator_args: [],
          fast_boot: true
        )
      end
    end

    described_class.new(
      source_kind: :staged_verilog,
      source_bundle_class: bundle_class,
      build_dir: File.join(@tmp_dir, 'build'),
      compile_now: false
    )

    expect(bundle_class.last_kwargs).to include(fast_boot: true, force_stub_hierarchy_sources: true)
  end

  it 'can be configured for JIT mode' do
    import_dir, = write_import_tree

    runner = described_class.new(
      import_dir: import_dir,
      build_dir: File.join(@tmp_dir, 'build'),
      compile_now: false,
      jit: true
    )

    expect(runner.jit?).to eq(true)
    expect(runner.runtime_contract_ready?).to eq(true)
  end

  it 'delegates run_cycles through the standard-ABI sim and returns a hash' do
    runner = build_runner_with_mock_sim(mock_sim)

    result = runner.run_cycles(12)

    expect(result).to be_a(Hash)
    expect(result[:cycles_run]).to eq(12)
    expect(runner.clock_count).to eq(12)
  end

  it 'delegates load_images through the standard-ABI sim' do
    runner = build_runner_with_mock_sim(mock_sim)

    runner.load_images(boot_image: [1, 2], program_image: [3, 4])

    expect(mock_sim.rom_loads).to eq([[RHDL::Examples::SPARC64::Integration::FLASH_BOOT_BASE, [1, 2]]])
    expect(mock_sim.memory_loads).to include(
      [0, [1, 2]],
      [RHDL::Examples::SPARC64::Integration::BOOT_PROM_ALIAS_BASE, [1, 2]],
      [RHDL::Examples::SPARC64::Integration::PROGRAM_BASE, [3, 4]]
    )
  end

  it 'returns normalized WishboneEvent structs from wishbone_trace' do
    runner = build_runner_with_mock_sim(mock_sim)

    trace = runner.wishbone_trace

    expect(trace).to eq(
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
  end

  it 'returns an array from unmapped_accesses' do
    runner = build_runner_with_mock_sim(mock_sim)

    expect(runner.unmapped_accesses).to eq([])
  end

  it 'reports compiled? as true when @sim is present' do
    runner = build_runner_with_mock_sim(mock_sim)

    expect(runner.compiled?).to eq(true)
  end

  it 'returns an empty hash from debug_snapshot' do
    runner = build_runner_with_mock_sim(mock_sim)

    expect(runner.debug_snapshot).to eq({})
  end

  it 'can compile the imported s1_top MLIR with arcilator', slow: true, timeout: 3600 do
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'arcilator not available' unless HdlToolchain.which('arcilator')
    skip 'clang not available' unless HdlToolchain.which('clang') || HdlToolchain.which('llc')

    import_dir = RHDL::Examples::SPARC64::Integration::ImportLoader.build_import_dir(fast_boot: true)
    runner = described_class.new(import_dir: import_dir, compile_now: true)

    expect(runner.compiled?).to eq(true)
    expect(runner.sim).not_to be_nil
    expect(File).to exist(runner.build_dir)
  end
end
