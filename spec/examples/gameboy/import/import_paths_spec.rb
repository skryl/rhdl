# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

require_relative '../../../../examples/gameboy/utilities/import/system_importer'

RSpec.describe 'GameBoy mixed import path coverage', slow: true do
  def require_reference_tree!
    skip 'GameBoy reference tree not available' unless Dir.exist?(RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_REFERENCE_ROOT)
    skip 'GameBoy files.qip not available' unless File.file?(RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_QIP_PATH)
  end

  def require_tool!(cmd)
    skip "#{cmd} not available" unless HdlToolchain.which(cmd)
  end

  it 'emits stable mixed staging/report paths and strict diagnostics', timeout: 1800 do
    require_reference_tree!
    require_tool!('ghdl')
    require_tool!('circt-verilog')

    Dir.mktmpdir('gameboy_import_paths_out') do |out_dir|
      Dir.mktmpdir('gameboy_import_paths_ws') do |workspace|
        importer = RHDL::Examples::GameBoy::Import::SystemImporter.new(
          output_dir: out_dir,
          workspace_dir: workspace,
          keep_workspace: true,
          clean_output: true,
          strict: true,
          progress: ->(_msg) {}
        )
        result = importer.run
        expect(result.success?).to be(true), Array(result.diagnostics).join("\n")
        expect(result.strategy_used).to eq(:mixed)

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch('success')).to be(true)
        expect(report.fetch('strict')).to be(true)
        expect(report.fetch('top')).to eq('gb')

        mixed = report.fetch('mixed_import')
        artifacts = report.fetch('artifacts')
        pure_root = mixed.fetch('pure_verilog_root')
        staged_entry = mixed.fetch('pure_verilog_entry_path')
        normalized_verilog = mixed.fetch('normalized_verilog_path')
        workspace_normalized_verilog = artifacts.fetch('workspace_normalized_verilog_path')
        workspace_core_mlir = artifacts.fetch('workspace_core_mlir_path')

        expect(File.file?(staged_entry)).to be(true)
        expect(File.file?(normalized_verilog)).to be(true)
        expect(File.file?(workspace_normalized_verilog)).to be(true)
        expect(File.file?(workspace_core_mlir)).to be(true)
        expect(staged_entry).to start_with(File.join(out_dir, '.mixed_import'))
        expect(normalized_verilog).to start_with(File.join(out_dir, '.mixed_import'))
        expect(pure_root).to start_with(File.join(out_dir, '.mixed_import'))
        expect(workspace_normalized_verilog).to start_with(File.join(workspace, 'import_artifacts'))
        expect(workspace_core_mlir).to start_with(File.join(workspace, 'import_artifacts'))
        expect(artifacts.fetch('pure_verilog_root')).to eq(pure_root)
        expect(artifacts.fetch('pure_verilog_entry_path')).to eq(staged_entry)
        expect(artifacts.fetch('core_mlir_path')).to eq(mixed.fetch('core_mlir_path'))
        expect(artifacts.fetch('normalized_verilog_path')).to eq(normalized_verilog)
        expect(mixed.fetch('workspace_normalized_verilog_path')).to eq(workspace_normalized_verilog)
        expect(mixed.fetch('workspace_core_mlir_path')).to eq(workspace_core_mlir)

        staged_content = File.read(staged_entry)
        expect(staged_content).to include(pure_root)
        expect(staged_content).not_to include(File.join(workspace, 'mixed_sources'))

        runtime_import_mlir = File.join(workspace, 'runtime_entry.core.mlir')
        runtime_import = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
          verilog_path: staged_entry,
          out_path: runtime_import_mlir,
          tool: 'circt-verilog'
        )
        expect(runtime_import[:success]).to be(true), <<~MSG
          Runtime staged Verilog should remain importable after path stabilization.
          Command: #{runtime_import[:command]}
          #{runtime_import[:stderr]}
        MSG
        expect(File.file?(runtime_import_mlir)).to be(true)

        video_source = File.join(pure_root, 'rtl', 'video.v')
        if File.file?(video_source)
          video_text = File.read(video_source)
          expect(video_text).to include('wire [7:0] spr_extra_tile0;')
          expect(video_text).to include('wire [7:0] spr_extra_tile1;')
          expect(video_text).not_to include('spr_extra_tile [0:1]')
        end

        import_errors = Array(report.fetch('import_diagnostics', [])).select { |diag| diag['severity'] == 'error' }
        raise_errors = Array(report.fetch('raise_diagnostics', [])).select { |diag| diag['severity'] == 'error' }
        expect(import_errors).to be_empty
        expect(raise_errors).to be_empty
      end
    end
  end
end
