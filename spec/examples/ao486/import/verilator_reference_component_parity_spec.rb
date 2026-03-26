# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_programs'
require_relative '../../../../examples/ao486/utilities/runners/verilator_runner'

RSpec.describe 'AO486 staged-Verilog Verilator compact benchmark smoke', slow: true do
  TOOLING_PATCHES_ROOT = File.expand_path('../../../../examples/ao486/patches/tooling', __dir__)

  def require_program_assembler!
    skip 'llvm-mc not available' unless HdlToolchain.which('llvm-mc')
    skip 'llvm-objcopy not available' unless HdlToolchain.which('llvm-objcopy')
  end

  def prepare_source_wrapper(patches_dir:)
    out_dir = Dir.mktmpdir('ao486_reference_component_out')
    workspace = Dir.mktmpdir('ao486_reference_component_ws')
    importer = RHDL::Examples::AO486::Import::CpuImporter.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true,
      import_strategy: :tree,
      patches_dir: patches_dir,
      strict: false
    )

    diagnostics = []
    command_log = []
    patch_result = importer.send(:prepare_import_source_tree, workspace, diagnostics: diagnostics, command_log: command_log)
    raise "patch prep failed:\n#{diagnostics.join("\n")}" unless patch_result[:success]

    [importer.send(:prepare_workspace, workspace, strategy: :tree), workspace]
  end

  def build_binary(prepared:, workspace:, work_dir:)
    runner = RHDL::Examples::AO486::VerilatorRunner.new(headless: true)
    cpp_path = File.join(work_dir, 'cpu_parity_tb.cpp')
    obj_dir = File.join(work_dir, 'obj_dir')
    FileUtils.mkdir_p(work_dir)
    File.write(cpp_path, runner.send(:verilator_harness_cpp))

    include_dirs = [
      workspace,
      File.join(workspace, 'tree'),
      File.join(workspace, 'tree', 'ao486')
    ]

    verilator_cmd = [
      'verilator',
      '--cc',
      '--top-module', 'ao486',
      '--x-assign', '0',
      '--x-initial', '0',
      '-Wno-fatal',
      '-Wno-UNOPTFLAT',
      '-Wno-PINMISSING',
      '-Wno-WIDTHEXPAND',
      '-Wno-WIDTHTRUNC',
      *include_dirs.map { |dir| "-I#{dir}" },
      '--Mdir', obj_dir,
      prepared.fetch(:wrapper_path),
      '--exe', cpp_path
    ]
    stdout, stderr, status = Open3.capture3(*verilator_cmd)
    raise "Verilator compile failed:\n#{stdout}\n#{stderr}" unless status.success?

    make_stdout, make_stderr, make_status = Open3.capture3('make', '-C', obj_dir, '-f', 'Vao486.mk')
    raise "Verilator make failed:\n#{make_stdout}\n#{make_stderr}" unless make_status.success?

    File.join(obj_dir, 'Vao486')
  end

  def normalize_memory(memory)
    memory.to_h.sort.to_h
  end

  def verify_expected_final_state!(state, program)
    expect(state.fetch('trace_wr_hlt_in_progress')).to eq(1), "program=#{program.name}"
    expect(state.fetch('trace_wr_ready')).to eq(1), "program=#{program.name}"
    program.expected_final_registers.each do |signal_name, expected_value|
      expect(state.fetch(signal_name)).to eq(expected_value), "program=#{program.name} signal=#{signal_name}"
    end
  end

  def run_program(binary:, work_dir:, program:)
    runner = RHDL::Examples::AO486::VerilatorRunner.new(headless: true)
    program.load_into(runner)
    runner.instance_variable_set(:@work_dir, work_dir)
    runner.instance_variable_set(:@binary_path, binary)

    step_trace = runner.send(:run_step_trace, max_cycles: program.max_cycles).map { |event| [event.eip, event.bytes] }
    state = runner.send(:run_final_state, max_cycles: program.max_cycles)
    verify_expected_final_state!(state, program)

    {
      step_trace: step_trace,
      state: state,
      memory: normalize_memory(runner.memory)
    }
  end

  def benchmark_results(patches_dir:, label:)
    Dir.mktmpdir("ao486_reference_component_build_#{label}") do |build_dir|
      prepared, workspace = prepare_source_wrapper(patches_dir: patches_dir)
      binary = build_binary(prepared: prepared, workspace: workspace, work_dir: File.join(build_dir, label))

      results = RHDL::Examples::AO486::Import::CpuParityPrograms.benchmark_programs.each_with_object({}) do |program, acc|
        acc[program.name] = run_program(binary: binary, work_dir: File.join(build_dir, label), program: program)
      end

      return results
    end
  end

  it 'completes the compact benchmark set with the direct staged-Verilog reference frontend', timeout: 1200 do
    require_program_assembler!
    skip 'verilator not available' unless HdlToolchain.verilator_available?

    reference_results = benchmark_results(patches_dir: TOOLING_PATCHES_ROOT, label: 'reference_components')

    RHDL::Examples::AO486::Import::CpuParityPrograms.benchmark_programs.each do |program|
      result = reference_results.fetch(program.name)
      expect(result.fetch(:step_trace)).not_to be_empty, "program=#{program.name}"
    end
  end
end
