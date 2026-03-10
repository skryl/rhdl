# frozen_string_literal: true

require_relative 'system_importer'

module RHDL
  module Examples
    module AO486
      module Import
        # Imports the AO486 CPU top (`ao486.v`) into CIRCT and raises it to RHDL DSL.
        # This importer is used for CPU-top runtime parity flows that need a canonical
        # imported MLIR artifact rooted at the full RTL tree.
        class CpuImporter < SystemImporter
          DEFAULT_SOURCE_ROOT = File.join(DEFAULT_REFERENCE_ROOT, 'rtl')
          DEFAULT_SOURCE_PATH = File.join(DEFAULT_SOURCE_ROOT, 'ao486', 'ao486.v')
          DEFAULT_TOP = 'ao486'
          DEFAULT_IMPORT_STRATEGY = :tree

          def initialize(source_path: DEFAULT_SOURCE_PATH,
                         output_dir:,
                         top: DEFAULT_TOP,
                         keep_workspace: false,
                         workspace_dir: nil,
                         clean_output: true,
                         import_strategy: DEFAULT_IMPORT_STRATEGY,
                         fallback_to_stubbed: false,
                         maintain_directory_structure: true,
                         patches_dir: nil,
                         format_output: false,
                         strict: false,
                         progress: nil)
            super(
              source_path: source_path,
              output_dir: output_dir,
              top: top,
              keep_workspace: keep_workspace,
              workspace_dir: workspace_dir,
              clean_output: clean_output,
              import_strategy: import_strategy,
              fallback_to_stubbed: fallback_to_stubbed,
              maintain_directory_structure: maintain_directory_structure,
              patches_dir: patches_dir,
              format_output: format_output,
              strict: strict,
              progress: progress
            )
          end

          private

          def prepare_workspace(workspace, strategy:, force_stub_modules: TREE_FORCE_STUB_MODULES)
            FileUtils.mkdir_p(workspace)
            force_stub_modules = Array(force_stub_modules).map(&:to_s).uniq
            current_source_root = import_source_search_root
            current_source_path = import_source_path

            staged_source_path = File.join(workspace, File.basename(current_source_path))
            stub_path = File.join(workspace, "stubs.#{strategy}.v")
            wrapper_path = File.join(workspace, "import_all.#{strategy}.sv")
            moore_mlir_path = File.join(workspace, "#{top}.#{strategy}.moore.mlir")
            core_mlir_path = File.join(workspace, "#{top}.#{strategy}.core.mlir")
            normalized_core_mlir_path = File.join(workspace, "#{top}.#{strategy}.normalized.core.mlir")

            FileUtils.cp(current_source_path, staged_source_path)
            normalize_source_file!(staged_source_path)

            include_paths = [staged_source_path]
            stub_ports = {}
            module_to_file, = build_module_index(current_source_root)
            module_source_relpaths = module_to_file.transform_values { |path| source_relative_path(path) }

            if strategy == :tree
              tree_module_files = stage_tree_module_files(workspace, force_stub_modules: force_stub_modules)
              include_paths.concat(tree_module_files)
            end

            include_paths.each do |path|
              merge_stub_ports!(stub_ports, extract_stub_ports(File.read(path)))
            end

            if strategy == :tree
              include_paths.reject! do |path|
                modules_in_file = extract_defined_modules(File.read(path))
                !(modules_in_file & force_stub_modules).empty?
              end
              force_stub_modules.each { |name| stub_ports[name] ||= { ports: [], params: [] } }
            end

            defined = include_paths.flat_map { |file| extract_defined_modules(File.read(file)) }.uniq
            stub_ports = stub_ports.reject { |module_name, _ports| defined.include?(module_name) }

            metadata = prepared_metadata(
              source_root: current_source_root,
              staged_source_path: staged_source_path,
              workspace: workspace,
              include_paths: include_paths,
              module_source_relpaths: module_source_relpaths
            )

            write_stub_file(stub_path, stub_ports)
            write_wrapper_file(wrapper_path, include_paths: include_paths, stub_path: stub_path)

            {
              strategy: strategy,
              staged_system_path: staged_source_path,
              stub_path: stub_path,
              wrapper_path: wrapper_path,
              moore_mlir_path: moore_mlir_path,
              core_mlir_path: core_mlir_path,
              normalized_core_mlir_path: normalized_core_mlir_path,
              stub_modules: stub_ports.keys.sort,
              module_source_relpaths: module_source_relpaths,
              command_chdir: (strategy == :tree ? workspace : nil)
            }.merge(metadata)
          end

          def discover_tree_module_files(force_stub_modules:)
            current_source_root = import_source_search_root
            module_to_file, module_to_body = build_module_index(current_source_root)
            force_stub_modules = Array(force_stub_modules).map(&:to_s).uniq

            needed_files = []
            seen_modules = {}
            queue = [top]

            until queue.empty?
              module_name = queue.shift
              next if seen_modules[module_name]

              seen_modules[module_name] = true
              next if force_stub_modules.include?(module_name) && module_name != top

              file = module_to_file[module_name]
              body = module_to_body[module_name]
              needed_files << file if file
              next unless body

              extract_instantiated_modules(body).each do |child|
                queue << child if module_to_body.key?(child) && !seen_modules[child]
              end
            end

            source_expanded = File.expand_path(import_source_path)
            needed_files.compact.uniq.sort.reject { |path| File.expand_path(path) == source_expanded }
          end

          def stage_tree_module_files(workspace, force_stub_modules:)
            source_root = import_source_search_root
            stage_root = File.join(workspace, 'tree')

            staged = discover_tree_module_files(force_stub_modules: force_stub_modules).map do |src|
              relative = src.delete_prefix("#{source_root}/")
              dst = File.join(stage_root, relative)
              FileUtils.mkdir_p(File.dirname(dst))
              File.write(dst, normalize_tree_source(
                File.read(src),
                stage_root: stage_root
              ))
              dst
            end

            stage_tree_include_helpers(source_root, workspace, stage_root)
            staged
          end

          def source_relative_path(path)
            root = import_source_search_root
            absolute = File.expand_path(path)
            prefix = "#{root}/"
            return absolute.delete_prefix(prefix) if absolute.start_with?(prefix)

            File.basename(absolute)
          end

          def source_search_root
            File.expand_path('..', File.dirname(source_path))
          end

          def normalize_source_file!(path)
            text = File.read(path)
            return if text.match?(/^\s*`timescale\b/m)

            File.write(path, "`timescale 1ns/1ps\n#{text}")
          end

          def normalize_core_mlir_text(text, diagnostics:)
            normalized = super
            cleanup = RHDL::Codegen::CIRCT::ImportCleanup.cleanup_imported_core_mlir(
              normalized,
              strict: false,
              top: top
            )
            Array(cleanup.import_result&.diagnostics).each do |diag|
              line = if diag.respond_to?(:severity) && diag.respond_to?(:message)
                       "[#{diag.severity}]#{diag.respond_to?(:op) && diag.op ? " #{diag.op}:" : ''} #{diag.message}"
                     else
                       diag.to_s
                     end
              diagnostics << line
            end
            cleanup.success? ? cleanup.cleaned_text : normalized
          end
        end
      end
    end
  end
end
