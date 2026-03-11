# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_programs'
require_relative '../../../../examples/ao486/utilities/runners/ir_runner'
require_relative '../../../../examples/ao486/utilities/runners/verilator_runner'

RSpec.describe 'AO486 CPU parity-package fetch parity', slow: true do
  include AO486SpecSupport::HeadlessImportRunnerHelper

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

  def require_ir_backend!
    backend = AO486SpecSupport::IRBackendHelper.cpu_runtime_ir_backend
    skip 'IR compiler/JIT backend unavailable' unless backend

    backend
  end

  it 'matches the selected IR backend and Verilator on the named AO486 parity programs', timeout: 900 do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_fetch_parity_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_fetch_parity_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        cleaned_mlir = File.read(result.normalized_core_mlir_path)

        ir_runtime = build_ao486_import_headless_runner(cleaned_mlir, mode: :ir, sim: backend)

        Dir.mktmpdir('ao486_cpu_fetch_parity_vl') do |build_dir|
          verilator_runtime = build_ao486_import_headless_runner(cleaned_mlir, mode: :verilog, work_dir: build_dir)

          RHDL::Examples::AO486::Import::CpuParityPrograms.all_programs.each do |program|
            program.load_into(ir_runtime)
            ir_trace = ir_runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

            program.load_into(verilator_runtime)
            verilator_trace = verilator_runtime.run_fetch_pc_groups(max_cycles: program.max_cycles).map { |event| [event.pc, event.bytes] }

            prefix = program.initial_fetch_pc_groups
            expect(ir_trace.first(prefix.length)).to eq(prefix), "program=#{program.name}"
            expect(verilator_trace.first(prefix.length)).to eq(prefix), "program=#{program.name}"
            expect(verilator_trace).to eq(ir_trace), "program=#{program.name}"
          end
        end
      end
    end
  end
end
