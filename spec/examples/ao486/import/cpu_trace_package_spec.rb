# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_programs'
require_relative '../../../../examples/ao486/utilities/import/cpu_trace_package'
require_relative '../../../../examples/ao486/utilities/runners/ir_runner'

RSpec.describe RHDL::Examples::AO486::Import::CpuTracePackage do
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

  def firtool_accepts?(mlir_text)
    return nil unless HdlToolchain.which('firtool')

    Dir.mktmpdir('ao486_cpu_trace_firtool') do |dir|
      in_path = File.join(dir, 'input.mlir')
      out_path = File.join(dir, 'output.v')
      File.write(in_path, mlir_text)
      system('firtool', in_path, '--verilog', '-o', out_path, out: File::NULL, err: File::NULL)
    end
  end

  def export_verilog(mlir_text)
    return nil unless HdlToolchain.which('firtool')

    Dir.mktmpdir('ao486_cpu_trace_export') do |dir|
      in_path = File.join(dir, 'input.mlir')
      out_path = File.join(dir, 'output.v')
      File.write(in_path, mlir_text)
      ok = system('firtool', in_path, '--verilog', '-o', out_path, out: File::NULL, err: File::NULL)
      return nil unless ok

      return File.read(out_path)
    end
  end

  def require_ir_backend!
    backend = AO486SpecSupport::IRBackendHelper.preferred_ir_backend
    skip 'IR compiler/JIT backend unavailable' unless backend

    backend
  end

  it 'adds stable retire-trace ports to the imported ao486 package', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_cpu_trace_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_trace_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        traced = described_class.from_cleaned_mlir(File.read(result.normalized_core_mlir_path))

        expect(traced[:success]).to be(true), Array(traced[:diagnostics]).join("\n")
        expect(traced[:package]).not_to be_nil
        expect(traced[:mlir]).to include('hw.module @ao486')

        traced_import = RHDL::Codegen.import_circt_mlir(traced[:mlir], strict: false, top: 'ao486')
        expect(traced_import.success?).to be(true), Array(traced_import.diagnostics).join("\n")

        ao486 = traced_import.modules.find { |mod| mod.name.to_s == 'ao486' }
        expect(ao486).not_to be_nil
        expect(ao486.ports.map { |port| [port.name.to_s, port.width.to_i] }).to include(
          ['trace_retired', 1],
          ['trace_wr_finished', 1],
          ['trace_wr_ready', 1],
          ['trace_wr_hlt_in_progress', 1],
          ['trace_wr_eip', 32],
          ['trace_wr_consumed', 4],
          ['trace_cs_cache', 64],
          ['trace_cs_cache_valid', 1],
          ['trace_prefetch_eip', 32],
          ['trace_fetch_valid', 4],
          ['trace_fetch_bytes', 64],
          ['trace_dec_acceptable', 4],
          ['trace_fetch_accept_length', 4],
          ['trace_arch_new_export', 1],
          ['trace_arch_eax', 32],
          ['trace_arch_ebx', 32],
          ['trace_arch_ecx', 32],
          ['trace_arch_edx', 32],
          ['trace_arch_esi', 32],
          ['trace_arch_edi', 32],
          ['trace_arch_esp', 32],
          ['trace_arch_ebp', 32],
          ['trace_arch_eip', 32]
        )

        pipeline = traced_import.modules.find { |mod| mod.name.to_s == 'pipeline' }
        expect(pipeline.ports.map(&:name).map(&:to_s)).to include(
          'trace_retired',
          'trace_wr_finished',
          'trace_wr_ready',
          'trace_wr_hlt_in_progress',
          'trace_cs_cache_valid',
          'trace_prefetch_eip',
          'trace_fetch_valid',
          'trace_fetch_bytes',
          'trace_dec_acceptable',
          'trace_fetch_accept_length',
          'trace_arch_new_export',
          'trace_arch_eax',
          'trace_arch_ebx',
          'trace_arch_ecx',
          'trace_arch_edx',
          'trace_arch_esi',
          'trace_arch_edi',
          'trace_arch_esp',
          'trace_arch_ebp',
          'trace_arch_eip'
        )

        write = traced_import.modules.find { |mod| mod.name.to_s == 'write' }
        expect(write.ports.map(&:name).map(&:to_s)).to include(
          'trace_wr_finished',
          'trace_wr_ready',
          'trace_wr_hlt_in_progress'
        )
      end
    end
  end

  it 'exports traced ao486 MLIR through firtool', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_cpu_trace_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_trace_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        traced = described_class.from_cleaned_mlir(File.read(result.normalized_core_mlir_path))

        expect(traced[:success]).to be(true), Array(traced[:diagnostics]).join("\n")

        firtool_result = firtool_accepts?(traced.fetch(:mlir))
        expect(firtool_result).not_to eq(false)

        verilog = export_verilog(traced.fetch(:mlir))
        next if verilog.nil?

        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_retired\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_wr_finished\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_wr_ready\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_wr_hlt_in_progress\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_cs_cache_valid\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_prefetch_eip\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_arch_eax\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_arch_edi\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_arch_eip\b/)
        expect(verilog).not_to include("assign trace_retired = 1'h0;")
      end
    end
  end

  it 'keeps top-level trace ports aligned with internal pipeline signals on the selected IR runtime', timeout: 240 do
    require_import_tool!
    require_program_assembler!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_trace_runtime_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_trace_runtime_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        runtime = build_ao486_import_headless_runner(
          File.read(result.normalized_core_mlir_path),
          mode: :ir,
          sim: backend
        )
        RHDL::Examples::AO486::Import::CpuParityPrograms.fetch(:prime_sieve).load_into(runtime)
        runtime.reset

        saw_fetch = false
        saw_write = false

        32.times do |cycle|
          runtime.step(cycle)
          if runtime.peek('pipeline_inst__trace_fetch_valid') > 0
            expect(runtime.peek('trace_prefetch_eip')).to eq(runtime.peek('pipeline_inst__trace_prefetch_eip'))
            expect(runtime.peek('trace_fetch_valid')).to eq(runtime.peek('pipeline_inst__trace_fetch_valid'))
            expect(runtime.peek('trace_fetch_accept_length')).to eq(runtime.peek('pipeline_inst__trace_fetch_accept_length'))
            saw_fetch = true
          end

          if runtime.peek('pipeline_inst.wr_eip') > 0
            expect(runtime.peek('trace_wr_eip')).to eq(runtime.peek('pipeline_inst.wr_eip'))
            expect(runtime.peek('trace_wr_consumed')).to eq(runtime.peek('pipeline_inst.wr_consumed'))
            expect(runtime.peek('trace_retired')).to eq(runtime.peek('pipeline_inst__trace_retired'))
            expect(runtime.peek('trace_arch_eax')).to eq(runtime.peek('pipeline_inst__trace_arch_eax'))
            expect(runtime.peek('trace_arch_edi')).to eq(runtime.peek('pipeline_inst__trace_arch_edi'))
            expect(runtime.peek('trace_arch_eip')).to eq(runtime.peek('pipeline_inst__trace_arch_eip'))
            saw_write = true
          end
        end

        expect(saw_fetch).to be(true)
        expect(saw_write).to be(true)
      end
    end
  end
end
