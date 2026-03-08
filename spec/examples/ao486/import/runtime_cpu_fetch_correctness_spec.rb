# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_programs'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_runtime'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_verilator_runtime'

RSpec.describe 'AO486 CPU parity-package compact benchmark correctness', slow: true do
  def require_import_tool!
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
    skip "#{tool} not available" unless HdlToolchain.which(tool)
  end

  def require_program_assembler!
    skip 'llvm-mc not available' unless HdlToolchain.which('llvm-mc')
    skip 'llvm-objcopy not available' unless HdlToolchain.which('llvm-objcopy')
  end

  def run_importer(out_dir:, workspace:)
    RHDL::Examples::AO486::Import::CpuImporter.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true,
      maintain_directory_structure: false
    ).run
  end

  it 'matches the exact expected fetch-PC traces on JIT and Verilator for the compact benchmark set', timeout: 900 do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    skip 'IR JIT backend unavailable' unless RHDL::Sim::Native::IR::JIT_AVAILABLE

    Dir.mktmpdir('ao486_cpu_fetch_correctness_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_fetch_correctness_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        cleaned_mlir = File.read(result.normalized_core_mlir_path)
        jit_runtime = RHDL::Examples::AO486::Import::CpuParityRuntime.build_from_cleaned_mlir(cleaned_mlir)

        Dir.mktmpdir('ao486_cpu_fetch_correctness_vl') do |build_dir|
          verilator_runtime = RHDL::Examples::AO486::Import::CpuParityVerilatorRuntime.build_from_cleaned_mlir(
            cleaned_mlir,
            work_dir: build_dir
          )

          RHDL::Examples::AO486::Import::CpuParityPrograms.benchmark_programs.each do |program|
            expected = program.expected_fetch_pc_trace
            expect(expected).not_to be_empty, "program=#{program.name}"

            program.load_into(jit_runtime)
            jit_trace = jit_runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

            program.load_into(verilator_runtime)
            verilator_trace = verilator_runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

            expect(jit_trace).to eq(expected), "program=#{program.name}"
            expect(verilator_trace).to eq(expected), "program=#{program.name}"
          end
        end
      end
    end
  end
end
