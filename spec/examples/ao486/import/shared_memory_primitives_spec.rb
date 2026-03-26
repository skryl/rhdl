# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'

RSpec.describe 'AO486 shared memory primitive staging' do
  it 'stages shared memories and does not stub altdpram or altsyncram' do
    Dir.mktmpdir('ao486_shared_memories_out') do |out_dir|
      Dir.mktmpdir('ao486_shared_memories_ws') do |workspace|
        importer = RHDL::Examples::AO486::Import::CpuImporter.new(
          output_dir: out_dir,
          workspace_dir: workspace,
          keep_workspace: true
        )

        diagnostics = []
        command_log = []
        prepared_source = importer.send(:prepare_import_source_tree, workspace, diagnostics: diagnostics, command_log: command_log)
        expect(prepared_source[:success]).to be(true), diagnostics.join("\n")

        prepared = importer.send(:prepare_workspace, workspace, strategy: :tree)

        expect(prepared[:stub_modules]).not_to include('altdpram')
        expect(prepared[:stub_modules]).not_to include('altsyncram')
        expect(prepared[:include_paths]).to include(File.join(workspace, 'tree', 'common', 'memories', 'altdpram.v'))
        expect(prepared[:include_paths]).to include(File.join(workspace, 'tree', 'common', 'memories', 'altsyncram.v'))
      end
    end
  end

  it 'imports altsyncram without duplicating sequential state names' do
    Dir.mktmpdir('ao486_shared_memories_out') do |out_dir|
      Dir.mktmpdir('ao486_shared_memories_ws') do |workspace|
        importer = RHDL::Examples::AO486::Import::CpuImporter.new(
          output_dir: out_dir,
          workspace_dir: workspace,
          keep_workspace: true,
          strict: false
        )
        result = importer.run
        expect(result.success?).to be(true), Array(result.diagnostics).join("\n")

        normalized_core_mlir = File.read(result.normalized_core_mlir_path)
        altsyncram_module = normalized_core_mlir[/hw\.module @altsyncram\b.*?^  }/m]
        expect(altsyncram_module).not_to be_nil

        firreg_names = altsyncram_module.scan(/^\s*(%[A-Za-z0-9_$.]+) = seq\.firreg/).flatten
        duplicate_names = firreg_names.group_by(&:itself).select { |_name, defs| defs.length > 1 }

        expect(duplicate_names).to be_empty, duplicate_names.keys.inspect
      end
    end
  end
end
