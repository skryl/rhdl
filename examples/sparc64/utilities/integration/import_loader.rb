# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'rhdl'
require 'pathname'

require_relative '../import/system_importer'
require_relative 'import_patch_set'

module RHDL
  module Examples
    module SPARC64
      module Integration
        module ImportLoader
          DEFAULT_IMPORT_DIR = File.expand_path('../../import', __dir__).freeze
          DEFAULT_BUILD_CACHE_ROOT = File.expand_path('../../../../tmp/sparc64_import_trees', __dir__).freeze
          DEFAULT_REFERENCE_ROOT = Import::SystemImporter::DEFAULT_REFERENCE_ROOT
          DEFAULT_IMPORT_TOP = 's1_top'
          DEFAULT_IMPORT_TOP_FILE = File.join(DEFAULT_REFERENCE_ROOT, 'os2wb', 's1_top.v').freeze

          class << self
            def resolve_import_dir(import_dir: nil)
              File.expand_path(import_dir || DEFAULT_IMPORT_DIR)
            end

            def loaded_from
              @loaded_from
            end

            def load_component_class(top: 'S1Top', import_dir: nil, fast_boot: false,
                                     build_cache_root: DEFAULT_BUILD_CACHE_ROOT,
                                     reference_root: DEFAULT_REFERENCE_ROOT,
                                     import_top: nil,
                                     import_top_file: nil,
                                     importer_class: Import::SystemImporter)
              resolved_import_dir =
                if import_dir
                  resolve_import_dir(import_dir: import_dir)
                elsif fast_boot
                  build_import_dir(
                    build_cache_root: build_cache_root,
                    reference_root: reference_root,
                    import_top: import_top || default_import_top(top),
                    import_top_file: import_top_file,
                    fast_boot: true,
                    importer_class: importer_class
                  )
                else
                  resolve_import_dir
                end

              load_tree!(import_dir: resolved_import_dir)
              constantize(top)
            end

            def build_import_dir(build_cache_root: DEFAULT_BUILD_CACHE_ROOT,
                                 reference_root: DEFAULT_REFERENCE_ROOT,
                                 import_top: DEFAULT_IMPORT_TOP,
                                 import_top_file: nil,
                                 fast_boot: false,
                                 patches_dir: nil,
                                 importer_class: Import::SystemImporter)
              resolved_reference_root = File.expand_path(reference_root)
              resolved_top_file = File.expand_path(import_top_file || default_import_top_file(reference_root: resolved_reference_root, import_top: import_top))
              resolved_patches_dir = ImportPatchSet.patches_dir(fast_boot: fast_boot, override: patches_dir)
              build_dir = File.join(File.expand_path(build_cache_root), build_digest(
                reference_root: resolved_reference_root,
                import_top: import_top,
                import_top_file: resolved_top_file,
                patches_dir: resolved_patches_dir,
                patch_files: ImportPatchSet.patch_files(fast_boot: fast_boot, override: patches_dir)
              ))
              return build_dir if import_tree_ready?(build_dir)

              FileUtils.mkdir_p(File.expand_path(build_cache_root))
              importer = importer_class.new(
                reference_root: resolved_reference_root,
                top: import_top,
                top_file: resolved_top_file,
                output_dir: build_dir,
                keep_workspace: false,
                clean_output: true,
                strict: false,
                patches_dir: resolved_patches_dir,
                emit_runtime_json: false,
                progress: ->(_message) {}
              )
              result = importer.run
              return build_dir if result.success?

              raise RuntimeError, "Unable to build SPARC64 import tree at #{build_dir}: #{Array(result.diagnostics).join("\n")}"
            end

            def load_tree!(import_dir: nil)
              resolved = resolve_import_dir(import_dir: import_dir)
              raise ArgumentError, "SPARC64 import directory not found: #{resolved}" unless Dir.exist?(resolved)
              return resolved if loaded_from == resolved

              if loaded_from && loaded_from != resolved
                raise ArgumentError,
                      "SPARC64 import tree already loaded from #{loaded_from}; cannot switch to #{resolved} in the same process"
              end

              require_directory_tree_with_retries(resolved)
              @loaded_from = resolved
              resolved
            end

            private

            def build_digest(reference_root:, import_top:, import_top_file:, patches_dir:, patch_files:)
              patch_digests = Array(patch_files).map do |path|
                [path, Digest::SHA256.file(path).hexdigest]
              end
              Digest::SHA256.hexdigest(
                JSON.generate(
                  reference_root: reference_root,
                  import_top: import_top,
                  import_top_file: import_top_file,
                  patches_dir: patches_dir,
                  patch_files: patch_digests,
                  importer_sha: Digest::SHA256.file(File.expand_path('../import/system_importer.rb', __dir__)).hexdigest,
                  helper_sha: Digest::SHA256.file(__FILE__).hexdigest
                )
              )
            end

            def default_import_top(class_name)
              class_name.to_s.split('::').last
                        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                        .downcase
            end

            def default_import_top_file(reference_root:, import_top:)
              File.join(reference_root, 'os2wb', "#{import_top}.v")
            end

            def import_tree_ready?(root)
              Dir.exist?(root) && Dir.glob(File.join(root, '**', '*.rb')).any?
            end

            def require_directory_tree_with_retries(root)
              files = Dir.glob(File.join(root, '**', '*.rb')).sort
              raise ArgumentError, "No Ruby HDL files found in #{root}" if files.empty?

              pending = files
              last_errors = {}

              while pending.any?
                progressed = false
                still_pending = []

                pending.each do |path|
                  begin
                    require path
                    progressed = true
                  rescue NameError => e
                    still_pending << path
                    last_errors[path] = e
                  end
                end

                break if still_pending.empty?
                unless progressed
                  details = still_pending.first(8).map do |path|
                    "#{Pathname.new(path).relative_path_from(Pathname.new(root))}: #{last_errors[path].message}"
                  end.join("\n")
                  raise RuntimeError, "Unable to resolve generated SPARC64 HDL tree:\n#{details}"
                end

                pending = still_pending
              end
            end

            def constantize(class_name)
              class_name.to_s.split('::').inject(Object) do |scope, name|
                scope.const_get(name, false)
              end
            end
          end
        end
      end
    end
  end
end
