# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'

RSpec.describe 'AO486 parity patch profile trace import surface' do
  def require_import_tool!
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
    skip "#{tool} not available" unless HdlToolchain.which(tool)
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

  def diagnostic_summary(result)
    lines = []
    diagnostics = result.respond_to?(:diagnostics) ? Array(result.diagnostics) : []
    lines.concat(diagnostics)
    extra_raise = result.respond_to?(:raise_diagnostics) ? Array(result.raise_diagnostics) : []
    extra_raise.each do |diag|
      lines << "[#{diag.severity}]#{diag.op ? " #{diag.op}:" : ''} #{diag.message}"
    end
    lines.join("\n")
  end

  def firtool_accepts?(mlir_text)
    return nil unless HdlToolchain.which('firtool')

    Dir.mktmpdir('ao486_trace_patch_profile_firtool') do |dir|
      in_path = File.join(dir, 'input.mlir')
      out_path = File.join(dir, 'output.v')
      File.write(in_path, mlir_text)
      system('firtool', in_path, '--verilog', '-o', out_path, out: File::NULL, err: File::NULL)
    end
  end

  def export_verilog(mlir_text)
    return nil unless HdlToolchain.which('firtool')

    Dir.mktmpdir('ao486_trace_patch_profile_export') do |dir|
      in_path = File.join(dir, 'input.mlir')
      out_path = File.join(dir, 'output.v')
      File.write(in_path, mlir_text)
      ok = system('firtool', in_path, '--verilog', '-o', out_path, out: File::NULL, err: File::NULL)
      return nil unless ok

      File.read(out_path)
    end
  end

  it 'adds stable trace ports through the parity patch profile at import time', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_trace_patch_profile_out') do |out_dir|
      Dir.mktmpdir('ao486_trace_patch_profile_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        expect(result.success?).to be(true), diagnostic_summary(result)

        imported = RHDL::Codegen.import_circt_mlir(
          File.read(result.normalized_core_mlir_path),
          strict: false,
          top: 'ao486'
        )
        expect(imported.success?).to be(true), Array(imported.diagnostics).join("\n")

        ao486 = imported.modules.find { |mod| mod.name.to_s == 'ao486' }
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
          ['trace_prefetchfifo_accept_empty', 1],
          ['trace_prefetchfifo_accept_do', 1],
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

        pipeline = imported.modules.find { |mod| mod.name.to_s == 'pipeline' }
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

        write = imported.modules.find { |mod| mod.name.to_s == 'write' }
        expect(write.ports.map(&:name).map(&:to_s)).to include(
          'trace_wr_finished',
          'trace_wr_ready',
          'trace_wr_hlt_in_progress'
        )
      end
    end
  end

  it 'exports the parity patch profile through firtool', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_trace_patch_profile_out') do |out_dir|
      Dir.mktmpdir('ao486_trace_patch_profile_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        expect(result.success?).to be(true), diagnostic_summary(result)

        patched_mlir = File.read(result.normalized_core_mlir_path)
        firtool_result = firtool_accepts?(patched_mlir)
        expect(firtool_result).not_to eq(false)

        verilog = export_verilog(patched_mlir)
        next if verilog.nil?

        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_retired\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_wr_finished\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_wr_ready\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_wr_hlt_in_progress\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_prefetch_eip\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_fetch_valid\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_arch_eax\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_arch_edi\b/)
        expect(verilog).to match(/\boutput\b[\s\S]*\btrace_arch_eip\b/)
        expect(verilog).not_to include("assign trace_retired = 1'h0;")
      end
    end
  end
end
