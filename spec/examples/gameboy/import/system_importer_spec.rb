# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'yaml'
require 'json'
require 'fileutils'

require_relative '../../../../examples/gameboy/utilities/import/system_importer'

RSpec.describe RHDL::Examples::GameBoy::Import::SystemImporter do
  def require_reference_tree!
    skip 'GameBoy reference tree not available' unless Dir.exist?(described_class::DEFAULT_REFERENCE_ROOT)
    skip 'GameBoy files.qip not available' unless File.file?(described_class::DEFAULT_QIP_PATH)
  end

  def new_importer(output_dir:)
    described_class.new(
      output_dir: output_dir,
      clean_output: false,
      keep_workspace: true,
      progress: ->(_msg) {}
    )
  end

  describe '#resolve_sources' do
    it 'resolves files.qip recursively with deterministic mixed source set' do
      require_reference_tree!

      Dir.mktmpdir('gameboy_import_resolve') do |out_dir|
        importer = new_importer(output_dir: out_dir)
        resolved = importer.resolve_sources

        expect(resolved[:top][:name]).to eq('gb')
        expect(resolved[:top][:file]).to eq(File.expand_path('examples/gameboy/reference/rtl/gb.v', Dir.pwd))
        expect(resolved[:top][:language]).to eq('verilog')

        files = resolved.fetch(:files)
        expect(files.length).to eq(47)
        expect(files.map { |entry| entry[:path] }.uniq.length).to eq(47)
        expect(files.all? { |entry| File.file?(entry[:path]) }).to be(true)

        ext_counts = files.each_with_object(Hash.new(0)) do |entry, counts|
          counts[File.extname(entry[:path]).downcase] += 1
        end
        expect(ext_counts.fetch('.v', 0)).to eq(26)
        expect(ext_counts.fetch('.sv', 0)).to eq(7)
        expect(ext_counts.fetch('.vhd', 0)).to eq(14)

        expect(files.any? { |entry| entry[:path].end_with?('/rtl/T80/T80.vhd') }).to be(true)
        expect(files.any? { |entry| entry[:path].end_with?('/rtl/T80/T80_ALU.vhd') }).to be(true)
      end
    end

    it 'produces stable source ordering across calls' do
      require_reference_tree!

      Dir.mktmpdir('gameboy_import_order') do |out_dir|
        importer = new_importer(output_dir: out_dir)
        first = importer.resolve_sources
        second = importer.resolve_sources

        first_paths = first.fetch(:files).map { |entry| entry[:path] }
        second_paths = second.fetch(:files).map { |entry| entry[:path] }
        expect(first_paths).to eq(second_paths)
      end
    end
  end

  describe '#write_manifest' do
    it 'writes a mixed import manifest with canonical top and source list' do
      require_reference_tree!

      Dir.mktmpdir('gameboy_import_manifest') do |out_dir|
        Dir.mktmpdir('gameboy_import_workspace') do |workspace|
          importer = new_importer(output_dir: out_dir)
          resolved = importer.resolve_sources
          manifest_path = importer.write_manifest(workspace: workspace, resolved: resolved)

          expect(File.file?(manifest_path)).to be(true)
          manifest = YAML.safe_load(File.read(manifest_path))

          expect(manifest.fetch('version')).to eq(1)
          expect(manifest.fetch('top').fetch('name')).to eq('gb')
          expect(manifest.fetch('top').fetch('file')).to end_with('/mixed_sources/rtl/gb.v')
          expect(File.file?(manifest.fetch('top').fetch('file'))).to be(true)
          expect(manifest.fetch('files').length).to eq(26)
          shim_paths = manifest.fetch('files').map { |entry| entry.fetch('path') }
          expect(shim_paths).to include(
            a_string_ending_with('/mixed_sources/altera_mf/altera_mf_components.vhd'),
            a_string_ending_with('/mixed_sources/altera_mf/altsyncram.vhd')
          )

          languages = manifest.fetch('files').map { |entry| entry.fetch('language') }.uniq.sort
          expect(languages).to eq(%w[verilog vhdl])
        end
      end
    end
  end

  describe '#run' do
    it 'delegates to mixed import task and cleans output contents before run' do
      require_reference_tree!

      fake_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
          @options = options
        end

        def run
          FileUtils.mkdir_p(@options.fetch(:out))
          File.write(File.join(@options.fetch(:out), 'generated_component.rb'), "# generated\n")
          File.write(@options.fetch(:report), "{}\n")
        end
      end

      Dir.mktmpdir('gameboy_import_run_out') do |out_dir|
        Dir.mktmpdir('gameboy_import_run_ws') do |workspace|
          File.write(File.join(out_dir, '.gitignore'), "# keep\n")
          stale_path = File.join(out_dir, 'stale.txt')
          File.write(stale_path, 'stale')

          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            progress: ->(_msg) {},
            import_task_class: fake_task_class
          )

          result = importer.run
          expect(result.success?).to be(true)
          expect(File.exist?(stale_path)).to be(false)
          expect(File.file?(File.join(out_dir, '.gitignore'))).to be(true)

          options = fake_task_class.last_options
          expect(options).not_to be_nil
          expect(options.fetch(:mode)).to eq(:mixed)
          expect(options.fetch(:top)).to eq('gb')
          expect(options.fetch(:out)).to eq(out_dir)
          expect(options.fetch(:format_output)).to eq(false)
          expect(options).not_to have_key(:arc_remove_llhd)
          expect(File.file?(options.fetch(:manifest))).to be(true)

          manifest = YAML.safe_load(File.read(options.fetch(:manifest)))
          expect(manifest.fetch('files').length).to eq(26)
          expect(result.files_written).to include(File.join(out_dir, 'generated_component.rb'))
          expect(File.file?(result.report_path)).to be(true)
        end
      end
    end

    it 'mirrors canonical import artifacts into the workspace and records their paths in the report' do
      require_reference_tree!

      fake_task_class = Class.new do
        def initialize(options)
          @options = options
        end

        def run
          out_dir = @options.fetch(:out)
          FileUtils.mkdir_p(File.join(out_dir, '.mixed_import', 'pure_verilog'))
          File.write(File.join(out_dir, 'generated_component.rb'), "# generated\n")

          core_mlir = File.join(out_dir, '.mixed_import', 'gb.core.mlir')
          normalized_verilog = File.join(out_dir, '.mixed_import', 'gb.normalized.v')
          pure_entry = File.join(out_dir, '.mixed_import', 'pure_verilog_entry.v')
          pure_root = File.join(out_dir, '.mixed_import', 'pure_verilog')

          File.write(core_mlir, "hw.module @gb() {\n  hw.output\n}\n")
          File.write(normalized_verilog, "module gb;\nendmodule\n")
          File.write(pure_entry, "`include \"#{File.join(pure_root, 'gb.v')}\"\n")
          File.write(File.join(pure_root, 'gb.v'), "module gb;\nendmodule\n")

          report = {
            success: true,
            strict: true,
            top: 'gb',
            module_count: 1,
            mixed_import: {
              top_name: 'gb',
              pure_verilog_root: pure_root,
              pure_verilog_entry_path: pure_entry,
              core_mlir_path: core_mlir,
              normalized_verilog_path: normalized_verilog
            },
            artifacts: {
              pure_verilog_root: pure_root,
              pure_verilog_entry_path: pure_entry,
              core_mlir_path: core_mlir,
              normalized_verilog_path: normalized_verilog
            }
          }
          File.write(@options.fetch(:report), JSON.pretty_generate(report))
        end
      end

      Dir.mktmpdir('gameboy_import_artifacts_out') do |out_dir|
        Dir.mktmpdir('gameboy_import_artifacts_ws') do |workspace|
          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: true,
            progress: ->(_msg) {},
            import_task_class: fake_task_class
          )

          result = importer.run
          expect(result.success?).to be(true)

          report = JSON.parse(File.read(result.report_path))
          artifacts = report.fetch('artifacts')
          expect(File.file?(artifacts.fetch('workspace_core_mlir_path'))).to be(true)
          expect(File.file?(artifacts.fetch('workspace_normalized_verilog_path'))).to be(true)
          expect(File.file?(artifacts.fetch('workspace_pure_verilog_entry_path'))).to be(true)
          expect(File.directory?(artifacts.fetch('workspace_pure_verilog_root'))).to be(true)
          expect(artifacts.fetch('workspace_normalized_verilog_path')).to start_with(File.join(workspace, 'import_artifacts'))
          expect(report.fetch('mixed_import').fetch('workspace_normalized_verilog_path')).to eq(
            artifacts.fetch('workspace_normalized_verilog_path')
          )
          expect(result.source_verilog_path).to eq(artifacts.fetch('workspace_normalized_verilog_path'))
        end
      end
    end
  end

end
