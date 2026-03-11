# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_programs'
require_relative '../../../../examples/ao486/utilities/runners/arcilator_runner'
require_relative '../../../../examples/ao486/utilities/runners/ir_runner'
require_relative '../../../../examples/ao486/utilities/runners/verilator_runner'

RSpec.describe 'AO486 CPU parity-package final architectural state parity', slow: true do
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
      patch_profile: :parity
    ).run
  end

  def require_ir_backend!
    backend = AO486SpecSupport::IRBackendHelper.cpu_runtime_ir_backend
    skip 'IR compiler/JIT backend unavailable' unless backend

    backend
  end

  it 'matches the selected IR backend, Verilator, and Arcilator on the final exported architectural state of the compact benchmark set', timeout: 1200 do
    require_import_tool!
    require_program_assembler!
    require_arcilator_toolchain!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_arch_state_parity_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_arch_state_parity_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        cleaned_mlir = File.read(result.normalized_core_mlir_path)
        ir_runtime = build_ao486_import_headless_runner(cleaned_mlir, mode: :ir, sim: backend)

        Dir.mktmpdir('ao486_cpu_arch_state_parity_vl') do |build_dir|
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
            program.load_into(ir_runtime)
            ir_runtime.run(max_cycles: program.max_cycles)
            ir_state = ir_runtime.final_state_snapshot
            expect(ir_state).not_to be_empty, "program=#{program.name}"
            expect(ir_state.fetch('trace_wr_hlt_in_progress')).to eq(1), "program=#{program.name}"
            expect(ir_state.fetch('trace_wr_ready')).to eq(1), "program=#{program.name}"
            program.expected_final_registers.each do |signal_name, expected_value|
              expect(ir_state.fetch(signal_name)).to eq(expected_value), "program=#{program.name} signal=#{signal_name}"
            end

            program.load_into(verilator_runtime)
            verilator_state = verilator_runtime.run_final_state(max_cycles: program.max_cycles)
            expect(verilator_state).not_to be_empty, "program=#{program.name}"
            expect(verilator_state.fetch('trace_wr_hlt_in_progress')).to eq(1), "program=#{program.name}"
            expect(verilator_state.fetch('trace_wr_ready')).to eq(1), "program=#{program.name}"
            program.expected_final_registers.each do |signal_name, expected_value|
              expect(verilator_state.fetch(signal_name)).to eq(expected_value), "program=#{program.name} signal=#{signal_name}"
            end

            program.load_into(arcilator_runtime)
            arcilator_state = arcilator_runtime.run_final_state(max_cycles: program.max_cycles)
            expect(arcilator_state).not_to be_empty, "program=#{program.name}"
            expect(arcilator_state.fetch('trace_wr_hlt_in_progress')).to eq(1), "program=#{program.name}"
            expect(arcilator_state.fetch('trace_wr_ready')).to eq(1), "program=#{program.name}"
            program.expected_final_registers.each do |signal_name, expected_value|
              expect(arcilator_state.fetch(signal_name)).to eq(expected_value), "program=#{program.name} signal=#{signal_name}"
            end

            expect(verilator_state).to eq(ir_state), "program=#{program.name}"
            expect(arcilator_state).to eq(ir_state), "program=#{program.name}"
          end
        end
      end
    end
  end
end
