# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'

RSpec.describe RHDL::Examples::AO486::Import::CpuImporter do
  def firtool_accepts?(mlir_text)
    return nil unless HdlToolchain.which('firtool')

    Dir.mktmpdir('ao486_cpu_import_firtool') do |dir|
      in_path = File.join(dir, 'input.mlir')
      out_path = File.join(dir, 'output.v')
      File.write(in_path, mlir_text)
      system('firtool', in_path, '--verilog', '-o', out_path, out: File::NULL, err: File::NULL)
    end
  end

  def require_import_tool!
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
    skip "#{tool} not available" unless HdlToolchain.which(tool)
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

  def run_importer(out_dir:, workspace:, maintain_directory_structure: true)
    described_class.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true,
      maintain_directory_structure: maintain_directory_structure
    ).run
  end

  it 'imports ao486.v through CIRCT and emits CPU artifacts needed for runtime parity', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_cpu_import_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_import_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)

        expect(result.strategy_requested).to eq(:tree)
        expect(result.strategy_used).to eq(:tree)
        expect(result.fallback_used).to be(false)
        expect(File.exist?(result.normalized_core_mlir_path)).to be(true)
        expect(result.files_written.map { |path| File.basename(path) }).to include('ao486.rb')
        expect(File.exist?(File.join(out_dir, 'ao486', 'ao486.rb'))).to be(true)
        expect(File.exist?(File.join(out_dir, 'cache', 'l1_icache.rb'))).to be(true)
        expect(File.exist?(File.join(out_dir, 'common', 'simple_mult.rb'))).to be(true)
      end
    end
  end

  it 'produces canonical CPU MLIR artifacts rooted at top ao486 and can raise runtime components', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_cpu_import_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_import_ws') do |workspace|
        result = run_importer(
          out_dir: out_dir,
          workspace: workspace,
          maintain_directory_structure: false
        )

        expect(File.basename(result.normalized_core_mlir_path)).to eq('ao486.tree.normalized.core.mlir')
        normalized = File.read(result.normalized_core_mlir_path)
        expect(normalized).to include('hw.module @ao486')
        expect(normalized).not_to include('llhd.')
        expect(normalized).not_to match(/!hw\.array</)
        expect(File.read(File.join(workspace, 'ao486.v'))).to include('`timescale 1ns/1ps')

        raised = RHDL::Codegen.raise_circt_components(normalized, top: 'ao486', strict: false)
        expect(raised.success?).to be(true), diagnostic_summary(raised)
        expect(raised.components).to include('ao486')

        firtool_result = firtool_accepts?(normalized)
        expect(firtool_result).not_to eq(false)
      end
    end
  end
end
