# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

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

  it 'imports files.qip subset end-to-end and emits mixed import report', timeout: 1800 do
    require_reference_tree!
    require_tool!('ghdl')
    require_tool!('circt-translate')

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

        mixed = report.fetch('mixed_import')
        expect(mixed.fetch('top_name')).to eq('gb')
        expect(mixed.fetch('top_file')).to satisfy do |path|
          path.end_with?('/mixed_sources/rtl/gb.v') || path.end_with?('/examples/gameboy/reference/rtl/gb.v')
        end
        expect([24, 47]).to include(mixed.fetch('source_files').length)
        expect(File.file?(mixed.fetch('staging_entry_path'))).to be(true)

        degrade_diags = Array(report.fetch('raise_diagnostics', [])).select do |diag|
          RAISE_DEGRADE_OPS.include?(diag['op'].to_s)
        end
        expect(degrade_diags).to be_empty, "Raise degrade diagnostics present:\n#{degrade_diags.map { |d| d['op'] }.join("\n")}"
      end
    end
  end
end
