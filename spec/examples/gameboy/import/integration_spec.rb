# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'digest'

require_relative '../../../../examples/gameboy/utilities/import/system_importer'

RSpec.describe 'GameBoy mixed import integration', slow: true do
  RAISE_DEGRADE_OPS = %w[
    raise.behavior
    raise.expr
    raise.memory_read
    raise.case
    raise.sequential
  ].freeze

  def require_reference_tree!
    skip 'GameBoy reference tree not available' unless Dir.exist?(RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_REFERENCE_ROOT)
    skip 'GameBoy files.qip not available' unless File.file?(RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_QIP_PATH)
  end

  def require_tool!(cmd)
    skip "#{cmd} not available" unless HdlToolchain.which(cmd)
  end

  def generated_tree_fingerprint(root)
    files = Dir.glob(File.join(root, '**', '*.rb')).sort
    payload = files.map do |abs_path|
      rel_path = abs_path.delete_prefix("#{root}/")
      "#{rel_path}:#{Digest::SHA256.file(abs_path).hexdigest}"
    end
    Digest::SHA256.hexdigest(payload.join("\n"))
  end

  it 'imports files.qip subset end-to-end and emits mixed import report', timeout: 1800 do
    require_reference_tree!
    require_tool!('ghdl')
    require_tool!('circt-verilog')

    Dir.mktmpdir('gameboy_import_out') do |out_dir|
      Dir.mktmpdir('gameboy_import_ws') do |workspace|
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
        expect(File.file?(result.report_path)).to be(true)
        expect(File.file?(result.mlir_path)).to be(true)
        expect(result.files_written).not_to be_empty

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch('success')).to be(true)
        expect(report.fetch('top')).to eq('gb')
        expect(report.fetch('module_count')).to be > 0
        expect(report.fetch('component_count')).to eq(report.fetch('module_count'))

        mixed = report.fetch('mixed_import')
        artifacts = report.fetch('artifacts')
        components = report.fetch('components')
        expect(mixed.fetch('top_name')).to eq('gb')
        expect(mixed.fetch('top_file')).to start_with(File.join(out_dir, '.mixed_import', 'pure_verilog'))
        expect(mixed.fetch('top_file')).to end_with('/rtl/gb.v')
        expect(mixed.fetch('source_files').length).to eq(26)
        expect(File.directory?(mixed.fetch('pure_verilog_root'))).to be(true)
        expect(File.file?(mixed.fetch('pure_verilog_entry_path'))).to be(true)
        expect(File.file?(mixed.fetch('runtime_json_path'))).to be(true)
        expect(File.file?(mixed.fetch('firtool_verilog_path'))).to be(true)
        expect(File.file?(mixed.fetch('normalized_verilog_path'))).to be(true)
        expect(File.file?(artifacts.fetch('workspace_runtime_json_path'))).to be(true)
        expect(File.file?(artifacts.fetch('workspace_normalized_verilog_path'))).to be(true)
        expect(File.file?(artifacts.fetch('workspace_firtool_verilog_path'))).to be(true)
        expect(File.file?(artifacts.fetch('workspace_core_mlir_path'))).to be(true)
        expect(artifacts.fetch('workspace_runtime_json_path')).to start_with(File.join(workspace, 'import_artifacts'))
        expect(artifacts.fetch('workspace_normalized_verilog_path')).to start_with(File.join(workspace, 'import_artifacts'))
        expect(artifacts.fetch('workspace_firtool_verilog_path')).to start_with(File.join(workspace, 'import_artifacts'))
        expect(artifacts.fetch('core_mlir_path')).to eq(result.mlir_path)
        expect(artifacts.fetch('runtime_json_path')).to eq(mixed.fetch('runtime_json_path'))
        expect(artifacts.fetch('normalized_verilog_path')).to eq(mixed.fetch('normalized_verilog_path'))
        expect(artifacts.fetch('firtool_verilog_path')).to eq(mixed.fetch('firtool_verilog_path'))
        expect(components).not_to be_empty
        gb_component = components.find { |entry| entry.fetch('verilog_module_name') == 'gb' }
        expect(gb_component).not_to be_nil
        expect(File.file?(gb_component.fetch('raised_rhdl_path'))).to be(true)
        expect(File.file?(gb_component.fetch('staged_verilog_path'))).to be(true)
        expect(gb_component.fetch('origin_kind')).to eq('source_verilog')
        expect(gb_component.fetch('keep_structure_relative_path')).to eq(File.join('rtl', 'gb.rb'))

        degrade_diags = Array(report.fetch('raise_diagnostics', [])).select do |diag|
          RAISE_DEGRADE_OPS.include?(diag['op'].to_s)
        end
        expect(degrade_diags).to be_empty, "Raise degrade diagnostics present:\n#{degrade_diags.map { |d| d['op'] }.join("\n")}"
      end
    end
  end

  it 'regenerates deterministically across repeated mixed imports', timeout: 1800 do
    require_reference_tree!
    require_tool!('ghdl')
    require_tool!('circt-verilog')

    Dir.mktmpdir('gameboy_import_det') do |tmp_root|
      out_a = File.join(tmp_root, 'out_a')
      out_b = File.join(tmp_root, 'out_b')
      ws_a = File.join(tmp_root, 'ws_a')
      ws_b = File.join(tmp_root, 'ws_b')

      importer_a = RHDL::Examples::GameBoy::Import::SystemImporter.new(
        output_dir: out_a,
        workspace_dir: ws_a,
        keep_workspace: true,
        clean_output: true,
        strict: true,
        progress: ->(_msg) {}
      )

      importer_b = RHDL::Examples::GameBoy::Import::SystemImporter.new(
        output_dir: out_b,
        workspace_dir: ws_b,
        keep_workspace: true,
        clean_output: true,
        strict: true,
        progress: ->(_msg) {}
      )

      result_a = importer_a.run
      expect(result_a.success?).to be(true), Array(result_a.diagnostics).join("\n")
      result_b = importer_b.run
      expect(result_b.success?).to be(true), Array(result_b.diagnostics).join("\n")

      files_a = Dir.glob(File.join(out_a, '**', '*.rb')).map { |path| path.delete_prefix("#{out_a}/") }.sort
      files_b = Dir.glob(File.join(out_b, '**', '*.rb')).map { |path| path.delete_prefix("#{out_b}/") }.sort
      expect(files_b).to eq(files_a)

      expect(generated_tree_fingerprint(out_b)).to eq(generated_tree_fingerprint(out_a))
    end
  end
end
