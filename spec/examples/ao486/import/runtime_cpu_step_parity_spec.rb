# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_programs'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_runtime'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_verilator_runtime'

RSpec.describe 'AO486 CPU parity-package current write-trace parity', slow: true do
  def flatten_step_trace(trace)
    trace.flat_map do |event|
      Array(event.bytes).each_with_index.map { |byte, idx| [event.eip + idx, byte] }
    end
  end

  def stable_programs
    %i[reset_smoke prime_sieve game_of_life].map do |name|
      RHDL::Examples::AO486::Import::CpuParityPrograms.fetch(name)
    end
  end

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

  it 'matches JIT and Verilator on the stable write-trace byte-stream subset', timeout: 900 do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    skip 'IR JIT backend unavailable' unless RHDL::Sim::Native::IR::JIT_AVAILABLE

    Dir.mktmpdir('ao486_cpu_step_parity_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_step_parity_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        cleaned_mlir = File.read(result.normalized_core_mlir_path)
        jit_runtime = RHDL::Examples::AO486::Import::CpuParityRuntime.build_from_cleaned_mlir(cleaned_mlir)

        Dir.mktmpdir('ao486_cpu_step_parity_vl') do |build_dir|
          verilator_runtime = RHDL::Examples::AO486::Import::CpuParityVerilatorRuntime.build_from_cleaned_mlir(
            cleaned_mlir,
            work_dir: build_dir
          )

          stable_programs.each do |program|
            program.load_into(jit_runtime)
            jit_trace = flatten_step_trace(jit_runtime.run(max_cycles: program.max_cycles))
            expect(jit_trace).not_to be_empty, "program=#{program.name}"

            program.load_into(verilator_runtime)
            verilator_trace = flatten_step_trace(verilator_runtime.run_step_trace(max_cycles: program.max_cycles))
            expect(verilator_trace).not_to be_empty, "program=#{program.name}"

            expect(verilator_trace).to eq(jit_trace), "program=#{program.name}"
          end
        end
      end
    end
  end
end
