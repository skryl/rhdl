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

  it 'reads the imported core MLIR path and exposes backend metadata' do
    import_dir, mlir_path, = write_import_tree

    runner = described_class.new(import_dir: import_dir, build_dir: File.join(@tmp_dir, 'build'), compile_now: false)

    expect(runner.import_dir).to eq(import_dir)
    expect(runner.core_mlir_path).to eq(mlir_path)
    expect(runner.backend).to eq(:arcilator)
    expect(runner.simulator_type).to eq(:hdl_arcilator)
    expect(runner.native?).to eq(true)
    expect(runner.compiled?).to eq(false)
    expect(runner.cleanup_mode).to eq(:syntax_only)
    expect(runner.subprocess_runtime?).to eq(true)
  end

  it 'prefers pre-raise core MLIR over normalized post-raise MLIR when both are present' do
    import_dir, mlir_path, _normalized_path = write_import_tree(normalized: true)

    runner = described_class.new(import_dir: import_dir, build_dir: File.join(@tmp_dir, 'build'), compile_now: false)

    expect(runner.core_mlir_path).to eq(mlir_path)
  end

  it 'can be configured for JIT-backed arcilator smoke execution' do
    import_dir, = write_import_tree

    runner = described_class.new(import_dir: import_dir, build_dir: File.join(@tmp_dir, 'build'), compile_now: false, jit: true)

    expect(runner.jit?).to eq(true)
    expect(runner.runtime_contract_ready?).to eq(true)
    expect(runner.subprocess_runtime?).to eq(true)
  end

  it 'runs compile-mode cycles through the runtime command loop' do
    import_dir, = write_import_tree
    runner = described_class.new(import_dir: import_dir, build_dir: File.join(@tmp_dir, 'build'), compile_now: false)

    allow(runner).to receive(:ensure_runtime_built!)
    allow(runner).to receive(:send_jit_command).with('RUN 12').and_return('RUN 12')

    expect(runner.run_cycles(12)).to eq(12)
    expect(runner.clock_count).to eq(12)
    expect(runner).to have_received(:send_jit_command).with('RUN 12')
  end

  it 'routes image loading through the JIT runtime command loop' do
    import_dir, = write_import_tree
    runner = described_class.new(import_dir: import_dir, build_dir: File.join(@tmp_dir, 'build'), compile_now: false, jit: true)

    allow(runner).to receive(:ensure_runtime_built!)
    allow(runner).to receive(:send_jit_command).and_return('OK')
    allow(runner).to receive(:send_jit_payload_command).and_return('OK 4')

    runner.load_images(boot_image: [1, 2], program_image: [3, 4])

    expect(runner).to have_received(:send_jit_command).with('CLEAR_MEMORY').ordered
    expect(runner).to have_received(:send_jit_payload_command).with("LOAD_FLASH #{RHDL::Examples::SPARC64::Integration::FLASH_BOOT_BASE}", [1, 2]).ordered
    expect(runner).to have_received(:send_jit_payload_command).with('LOAD_MEMORY 0', [1, 2]).ordered
    expect(runner).to have_received(:send_jit_payload_command).with("LOAD_MEMORY #{RHDL::Examples::SPARC64::Integration::BOOT_PROM_ALIAS_BASE}", [1, 2]).ordered
    expect(runner).to have_received(:send_jit_payload_command).with("LOAD_MEMORY #{RHDL::Examples::SPARC64::Integration::PROGRAM_BASE}", [3, 4]).ordered
    expect(runner).to have_received(:send_jit_command).with('RESET').ordered
  end

  it 'parses JIT trace and fault payloads through the runtime contract' do
    import_dir, = write_import_tree
    runner = described_class.new(import_dir: import_dir, build_dir: File.join(@tmp_dir, 'build'), compile_now: false, jit: true)

    trace_words = [134, 1, 0x1000, 0xFF, 0x55, 0, 140, 0, 0x1008, 0xF0, 0, 0xAA]
    fault_words = [200, 1, 0x2000, 0x80]
    trace_hex = [trace_words.pack('Q<*')].pack('m0').unpack1('m0').unpack1('H*')
    fault_hex = [fault_words.pack('Q<*')].pack('m0').unpack1('m0').unpack1('H*')

    allow(runner).to receive(:ensure_runtime_built!)
    allow(runner).to receive(:send_jit_command).with('TRACE').and_return("TRACE 2 #{trace_hex}")
    allow(runner).to receive(:send_jit_command).with('FAULTS').and_return("FAULTS 1 #{fault_hex}")

    expect(runner.wishbone_trace).to eq([
                                        { cycle: 134, op: :write, addr: 0x1000, sel: 0xFF, write_data: 0x55, read_data: nil },
                                        { cycle: 140, op: :read, addr: 0x1008, sel: 0xF0, write_data: nil, read_data: 0xAA }
                                      ])
    expect(runner.unmapped_accesses).to eq([
                                            { cycle: 200, op: :write, addr: 0x2000, sel: 0x80 }
                                          ])
  end

  it 'prepares ARC MLIR and invokes arcilator with the expected observe flags' do
    import_dir, mlir_path = write_import_tree
    runner = described_class.new(import_dir: import_dir, build_dir: File.join(@tmp_dir, 'build'), compile_now: false)

    allow(runner).to receive(:check_tools_available!)
    prepared = {
      success: true,
      arc_mlir_path: File.join(@tmp_dir, 'build', 'arc', 's1_top.arc.mlir'),
      unsupported_modules: [],
      arc: { stderr: '', command: 'circt-opt ... --convert-to-arcs' }
    }
    allow(RHDL::Codegen::CIRCT::Tooling).to receive(:prepare_arc_mlir_from_circt_mlir).and_return(prepared)
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return(['ok', '', status])
    allow(runner).to receive(:parse_state_file!).and_return(
      module_name: 's1_top',
      state_size: 64,
      signals: {
        sys_clock_i: { offset: 0, bits: 1 },
        sys_reset_i: { offset: 1, bits: 1 },
        eth_irq_i: { offset: 2, bits: 1 },
        wbm_ack_i: { offset: 3, bits: 1 },
        wbm_data_i: { offset: 8, bits: 64 },
        wbm_cycle_o: { offset: 16, bits: 1 },
        wbm_strobe_o: { offset: 17, bits: 1 },
        wbm_we_o: { offset: 18, bits: 1 },
        wbm_addr_o: { offset: 24, bits: 64 },
        wbm_data_o: { offset: 32, bits: 64 },
        wbm_sel_o: { offset: 40, bits: 8 }
      }
    )
    allow(runner).to receive(:build_runtime_executable!)

    result = runner.build!

    expect(RHDL::Codegen::CIRCT::Tooling).to have_received(:prepare_arc_mlir_from_circt_mlir).with(
      mlir_path: mlir_path,
      work_dir: File.join(@tmp_dir, 'build', 'arc'),
      base_name: 's1_top',
      top: 's1_top',
      cleanup_mode: :syntax_only
    )
    expect(Open3).to have_received(:capture3).with(
      'arcilator',
      prepared[:arc_mlir_path],
      '--split-funcs-threshold=100',
      '--observe-ports',
      '--observe-wires',
      '--observe-registers',
      "--state-file=#{File.join(@tmp_dir, 'build', 's1_top.state.json')}",
      '-o',
      File.join(@tmp_dir, 'build', 's1_top.arc.ll')
    )
    expect(result[:success]).to eq(true)
    expect(result[:phase]).to eq(:runtime_link)
    expect(result[:command]).to include('arcilator')
    expect(result[:runtime_executable_path]).to eq(File.join(@tmp_dir, 'build', 's1_top.arc_runtime'))
    expect(File).to exist(File.join(@tmp_dir, 'build', 'arcilator.log'))
  end

  it 'builds linked JIT bitcode when requested' do
    import_dir, mlir_path = write_import_tree
    runner = described_class.new(import_dir: import_dir, build_dir: File.join(@tmp_dir, 'build'), compile_now: false, jit: true)

    allow(runner).to receive(:check_tools_available!)
    prepared = {
      success: true,
      arc_mlir_path: File.join(@tmp_dir, 'build', 'arc', 's1_top.arc.mlir'),
      unsupported_modules: [],
      arc: { stderr: '', command: 'circt-opt ... --convert-to-arcs' }
    }
    allow(RHDL::Codegen::CIRCT::Tooling).to receive(:prepare_arc_mlir_from_circt_mlir).and_return(prepared)
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return(['ok', '', status])
    allow(runner).to receive(:parse_state_file!).and_return(
      module_name: 's1_top',
      state_size: 64,
      signals: {
        sys_clock_i: { offset: 0, bits: 1 },
        sys_reset_i: { offset: 1, bits: 1 },
        eth_irq_i: { offset: 2, bits: 1 },
        wbm_ack_i: { offset: 3, bits: 1 },
        wbm_data_i: { offset: 8, bits: 64 },
        wbm_cycle_o: { offset: 16, bits: 1 },
        wbm_strobe_o: { offset: 17, bits: 1 },
        wbm_we_o: { offset: 18, bits: 1 },
        wbm_addr_o: { offset: 24, bits: 64 },
        wbm_data_o: { offset: 32, bits: 64 },
        wbm_sel_o: { offset: 40, bits: 8 }
      }
    )

    result = runner.build!

    expect(RHDL::Codegen::CIRCT::Tooling).to have_received(:prepare_arc_mlir_from_circt_mlir).with(
      mlir_path: mlir_path,
      work_dir: File.join(@tmp_dir, 'build', 'arc'),
      base_name: 's1_top',
      top: 's1_top',
      cleanup_mode: :syntax_only
    )
    expect(Open3).to have_received(:capture3).with(
      'arcilator',
      prepared[:arc_mlir_path],
      '--split-funcs-threshold=100',
      '--observe-ports',
      '--observe-wires',
      '--observe-registers',
      "--state-file=#{File.join(@tmp_dir, 'build', 's1_top.state.json')}",
      '-o',
      File.join(@tmp_dir, 'build', 's1_top.arc.ll')
    )
    expect(Open3).to have_received(:capture3).with(
      'clang++',
      '-std=c++17',
      '-O0',
      '-S',
      '-emit-llvm',
      '-DARCI_JIT_MAIN',
      File.join(@tmp_dir, 'build', 's1_top.arc_jit_main.cpp'),
      '-o',
      File.join(@tmp_dir, 'build', 's1_top.arc_jit_main.ll')
    )
    expect(Open3).to have_received(:capture3).with(
      'llvm-link',
      File.join(@tmp_dir, 'build', 's1_top.arc.ll'),
      File.join(@tmp_dir, 'build', 's1_top.arc_jit_main.ll'),
      '-o',
      File.join(@tmp_dir, 'build', 's1_top.arc_jit.bc')
    )
    expect(result[:success]).to eq(true)
    expect(result[:phase]).to eq(:jit_link)
    expect(result[:jit]).to eq(true)
    expect(result[:jit_bitcode_path]).to eq(File.join(@tmp_dir, 'build', 's1_top.arc_jit.bc'))
  end

  it 'compiles runtime objects with llc for compile mode' do
    import_dir, = write_import_tree
    runner = described_class.new(import_dir: import_dir, build_dir: File.join(@tmp_dir, 'build'), compile_now: false)
    status = instance_double(Process::Status, success?: true)
    FileUtils.mkdir_p(File.join(@tmp_dir, 'build'))

    allow(Open3).to receive(:capture3).and_return(['', '', status])

    runner.send(
      :compile_llvm_ir_object!,
      ll_path: File.join(@tmp_dir, 'build', 's1_top.arc_runtime.bc'),
      obj_path: File.join(@tmp_dir, 'build', 's1_top.arc.o')
    )

    expected_cmd = [
      'llc',
      '-filetype=obj',
      '-O0',
      '-relocation-model=pic'
    ]
    expected_cmd << '--aarch64-enable-global-isel-at-O=-1' if RbConfig::CONFIG['host_cpu'] =~ /(arm64|aarch64)/i
    expected_cmd += [
      File.join(@tmp_dir, 'build', 's1_top.arc_runtime.bc'),
      '-o',
      File.join(@tmp_dir, 'build', 's1_top.arc.o')
    ]

    expect(Open3).to have_received(:capture3).with(*expected_cmd)
  end

  it 'surfaces ARC preparation failures without invoking arcilator' do
    import_dir, = write_import_tree
    runner = described_class.new(import_dir: import_dir, build_dir: File.join(@tmp_dir, 'build'), compile_now: false)

    allow(runner).to receive(:check_tools_available!)
    allow(RHDL::Codegen::CIRCT::Tooling).to receive(:prepare_arc_mlir_from_circt_mlir).and_return(
      success: false,
      arc_mlir_path: nil,
      unsupported_modules: [{ 'module' => 's1_top', 'reason' => 'unsupported arc pattern' }],
      arc: {
        stderr: 'Unsupported ARC preparation patterns',
        command: 'circt-opt ... --convert-to-arcs'
      }
    )
    allow(Open3).to receive(:capture3)

    result = runner.build!

    expect(result[:success]).to eq(false)
    expect(result[:phase]).to eq(:prepare)
    expect(result[:stderr]).to include('Unsupported ARC preparation patterns')
    expect(Open3).not_to have_received(:capture3)
  end

  it 'runs a JIT smoke loop against the linked arcilator bitcode' do
    import_dir, = write_import_tree
    runner = described_class.new(import_dir: import_dir, build_dir: File.join(@tmp_dir, 'build'), compile_now: false, jit: true)

    runner.instance_variable_set(
      :@build_result,
      {
        success: true,
        jit_bitcode_path: File.join(@tmp_dir, 'build', 's1_top.arc_jit.bc')
      }
    )
    allow(runner).to receive(:ensure_runtime_built!)
    allow(runner).to receive(:send_jit_command).with('SMOKE 12 3').and_return('SMOKE 12 3 0 0 0 0 0 0')

    result = runner.run_jit_smoke!(cycles: 12, reset_cycles: 3)

    expect(result[:success]).to eq(true)
    expect(result[:stdout]).to include('JIT_OK')
    expect(result[:stdout]).to include('cycles=12')
  end

  it 'can compile the imported s1_top MLIR with arcilator', slow: true, timeout: 3600 do
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'arcilator not available' unless HdlToolchain.which('arcilator')
    skip 'clang++ not available' unless HdlToolchain.which('clang++')
    skip 'llvm-link not available' unless HdlToolchain.which('llvm-link')
    skip 'llc not available' unless HdlToolchain.which('llc')

    import_dir = RHDL::Examples::SPARC64::Integration::ImportLoader.build_import_dir(fast_boot: true)
    runner = described_class.new(import_dir: import_dir, compile_now: true)

    expect(runner.build_result[:success]).to eq(true), runner.build_result[:stderr]
    expect(File).to exist(runner.build_result[:llvm_ir_path])
    expect(File).to exist(runner.build_result[:state_path])
    expect(File).to exist(runner.build_result[:runtime_executable_path])
  end

  it 'can build and run the imported s1_top MLIR with arcilator JIT', slow: true, timeout: 3600 do
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'arcilator not available' unless HdlToolchain.which('arcilator')
    skip 'clang++ not available' unless HdlToolchain.which('clang++')
    skip 'llvm-link not available' unless HdlToolchain.which('llvm-link')
    skip 'lli not available' unless HdlToolchain.which('lli')

    import_dir = RHDL::Examples::SPARC64::Integration::ImportLoader.build_import_dir(fast_boot: true)
    runner = described_class.new(import_dir: import_dir, compile_now: true, jit: true)
    smoke = runner.run_jit_smoke!(cycles: 32, reset_cycles: 4)

    expect(runner.build_result[:success]).to eq(true), runner.build_result[:stderr]
    expect(File).to exist(runner.build_result[:jit_bitcode_path])
    expect(smoke[:success]).to eq(true), smoke[:stderr]
    expect(smoke[:stdout]).to include('JIT_OK')
  end
end
