# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_programs'
require_relative '../../../../examples/ao486/utilities/runners/arcilator_runner'
require_relative '../../../../examples/ao486/utilities/runners/ir_runner'
require_relative '../../../../examples/ao486/utilities/runners/verilator_runner'

RSpec.describe 'AO486 CPU parity-package compact benchmark correctness', slow: true do
  include AO486SpecSupport::HeadlessImportRunnerHelper

  def require_import_tool!
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
    skip "#{tool} not available" unless HdlToolchain.which(tool)
  end

  def require_program_assembler!
    skip 'llvm-mc not available' unless HdlToolchain.which('llvm-mc')
    skip 'llvm-objcopy not available' unless HdlToolchain.which('llvm-objcopy')
  end

  def require_arcilator_toolchain!
    skip 'arcilator not available' unless HdlToolchain.which('arcilator')
    return if (HdlToolchain.which('clang') || HdlToolchain.which('llc')) && HdlToolchain.which('c++')
    return if HdlToolchain.which('lli') && HdlToolchain.which('llvm-link') && HdlToolchain.which('clang++')

    skip 'Neither clang/llc+c++ nor lli/llvm-link/clang++ is available for the Arcilator harness'
  end

  def run_importer(out_dir:, workspace:)
    RHDL::Examples::AO486::Import::CpuImporter.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true,
      maintain_directory_structure: false,
      patches_dir: RHDL::Examples::AO486::Import::CpuImporter::DEFAULT_PATCHES_ROOT
    ).run
  end

  def require_ir_backend!
    backend = AO486SpecSupport::IRBackendHelper.cpu_runtime_ir_backend
    skip 'IR compiler/JIT backend unavailable' unless backend

    backend
  end

  it 'matches the expected fetch-PC prefixes on the selected IR backend, Verilator, and Arcilator for the compact benchmark set', timeout: 1200 do
    require_import_tool!
    require_program_assembler!
    require_arcilator_toolchain!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_fetch_correctness_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_fetch_correctness_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        cleaned_mlir = File.read(result.normalized_core_mlir_path)
        ir_runtime = build_ao486_import_headless_runner(cleaned_mlir, mode: :ir, sim: backend)

        Dir.mktmpdir('ao486_cpu_fetch_correctness_vl') do |build_dir|
          verilator_runtime = build_ao486_import_headless_runner(
            cleaned_mlir,
            mode: :verilog,
            work_dir: File.join(build_dir, 'verilator')
          )
          arcilator_runtime = build_ao486_import_headless_runner(
            cleaned_mlir,
            mode: :circt,
            work_dir: File.join(build_dir, 'arcilator')
          )

          RHDL::Examples::AO486::Import::CpuParityPrograms.benchmark_programs.each do |program|
            expected = program.expected_fetch_pc_trace
            expect(expected).not_to be_empty, "program=#{program.name}"

            program.load_into(ir_runtime)
            ir_trace = ir_runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

            program.load_into(verilator_runtime)
            verilator_trace = verilator_runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

            program.load_into(arcilator_runtime)
            arcilator_trace = arcilator_runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

            expect(ir_trace.length).to be >= expected.length, "program=#{program.name}"
            expect(verilator_trace.length).to be >= expected.length, "program=#{program.name}"
            expect(arcilator_trace.length).to be >= expected.length, "program=#{program.name}"
            expect(ir_trace.first(expected.length)).to eq(expected), "program=#{program.name}"
            expect(verilator_trace.first(expected.length)).to eq(expected), "program=#{program.name}"
            expect(arcilator_trace.first(expected.length)).to eq(expected), "program=#{program.name}"
          end
        end
      end
    end
  end
end
