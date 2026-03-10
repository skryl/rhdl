# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'

require_relative '../import/system_importer'
require_relative 'import_patch_set'

module RHDL
  module Examples
    module SPARC64
      module Integration
        class StagedVerilogBundle
          DEFAULT_REFERENCE_ROOT = File.expand_path('../../reference', __dir__).freeze
          DEFAULT_TOP = 's1_top'
          DEFAULT_TOP_FILE = File.join(DEFAULT_REFERENCE_ROOT, 'os2wb', 's1_top.v').freeze
          DEFAULT_CACHE_ROOT = File.expand_path('../../../../tmp/sparc64_verilator_sources', __dir__).freeze
          FAST_BOOT_PATCHES_DIR = ImportPatchSet::FAST_BOOT_PATCH_DIR
          FAST_BOOT_MEM_SIZE = ImportPatchSet::FAST_BOOT_MEM_SIZE
          FAST_BOOT_PATCH_TARGETS = ImportPatchSet::FAST_BOOT_PATCH_TARGETS

          Result = Struct.new(
            :build_dir,
            :staged_root,
            :top_module,
            :top_file,
            :include_dirs,
            :source_files,
            :verilator_args,
            :fast_boot,
            keyword_init: true
          )

          attr_reader :cache_root, :reference_root, :top, :top_file, :fast_boot

          def initialize(cache_root: DEFAULT_CACHE_ROOT, reference_root: DEFAULT_REFERENCE_ROOT,
                         top: DEFAULT_TOP, top_file: DEFAULT_TOP_FILE, fast_boot: true)
            @cache_root = File.expand_path(cache_root)
            @reference_root = File.expand_path(reference_root)
            @top = top.to_s
            @top_file = File.expand_path(top_file)
            @fast_boot = !!fast_boot
          end

          def build
            build_dir = File.join(cache_root, bundle_digest)
            manifest_path = File.join(build_dir, 'bundle.json')
            return load_result(manifest_path) if File.file?(manifest_path)

            FileUtils.mkdir_p(build_dir)
            importer = build_importer(workspace_dir: build_dir)
            resolved = importer.resolve_sources(workspace: build_dir)
            bundle = importer.write_import_source_bundle(workspace: build_dir, resolved: resolved)
            result = Result.new(
              build_dir: build_dir,
              staged_root: bundle.fetch(:staged_root),
              top_module: top,
              top_file: bundle.fetch(:staged_top_file),
              include_dirs: bundle.fetch(:staged_include_dirs),
              source_files: bundle.fetch(:tool_args).grep_v(/\A-/),
              verilator_args: bundle.fetch(:tool_args),
              fast_boot: fast_boot
            )
            File.write(manifest_path, JSON.pretty_generate(result.to_h))
            result
          end

          private

          def build_importer(workspace_dir: nil)
            Import::SystemImporter.new(
              reference_root: reference_root,
              top: top,
              top_file: top_file,
              output_dir: File.join(cache_root, '_unused'),
              workspace_dir: workspace_dir,
              keep_workspace: true,
              clean_output: false,
              strict: false,
              patches_dir: patches_dir,
              emit_runtime_json: false,
              progress: ->(_message) {}
            )
          end

          def load_result(manifest_path)
            data = JSON.parse(File.read(manifest_path))
            Result.new(
              build_dir: data.fetch('build_dir'),
              staged_root: data.fetch('staged_root'),
              top_module: data.fetch('top_module'),
              top_file: data.fetch('top_file'),
              include_dirs: data.fetch('include_dirs'),
              source_files: data.fetch('source_files'),
              verilator_args: data.fetch('verilator_args'),
              fast_boot: data.fetch('fast_boot')
            )
          end

          def bundle_digest
            digested = digest_input_files.map do |path|
              [path, Digest::SHA256.file(path).hexdigest]
            end
            Digest::SHA256.hexdigest(
              JSON.generate(
                top: top,
                top_file: top_file,
                fast_boot: fast_boot,
                patches_dir: patches_dir,
                files: digested,
                importer_sha: Digest::SHA256.file(File.expand_path('../import/system_importer.rb', __dir__)).hexdigest,
                helper_sha: Digest::SHA256.file(__FILE__).hexdigest
              )
            )
          end

          def digest_input_files
            reference_inputs = Dir.glob(File.join(reference_root, '**', '*')).select do |path|
              File.file?(path) && !binary_file?(path)
            end
            (reference_inputs + patch_input_files).uniq.sort
          end

          def patch_input_files
            ImportPatchSet.patch_files(fast_boot: fast_boot)
          end

          def patches_dir
            ImportPatchSet.patches_dir(fast_boot: fast_boot)
          end

          def binary_file?(path)
            File.binread(path, 1024).include?("\0")
          rescue StandardError
            true
          end
        end
      end
    end
  end
end
