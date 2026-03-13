# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'set'
require 'tmpdir'

require_relative '../../../examples/sparc64/utilities/import/system_importer'

module Sparc64UnitSupport
  class RuntimeImportSession
    ModuleRecord = Struct.new(
      :module_name,
      :class_name,
      :component_class,
      :source_path,
      :source_relative_path,
      :staged_source_path,
      :generated_ruby_path,
      :generated_ruby_relative_path,
      keyword_init: true
    )

    class << self
      def current
        mutex.synchronize do
          @current ||= new
          @current.prepare!
        end
      end

      def cleanup_current!
        mutex.synchronize do
          @current&.cleanup!
          @current = nil
        end
      end

      private

      def mutex
        @mutex ||= Mutex.new
      end
    end

    attr_reader :temp_root, :output_dir, :workspace_dir, :import_result, :inventory_records,
                :inventory_by_module_name, :inventory_by_source_relative_path, :import_run_count,
                :emitted_ruby_records

    def initialize(importer_class: RHDL::Examples::SPARC64::Import::SystemImporter,
                   temp_root: nil,
                   progress: nil)
      @importer_class = importer_class
      @temp_root = File.expand_path(temp_root || Dir.mktmpdir('rhdl_sparc64_unit_suite'))
      @output_dir = File.join(@temp_root, 'output')
      @workspace_dir = File.join(@temp_root, 'workspace')
      @progress = progress || ->(_message) {}
      @inventory_records = []
      @inventory_by_module_name = {}
      @inventory_by_source_relative_path = {}
      @emitted_ruby_records = []
      @suite_raise_diagnostics = nil
      @report_data = nil
      @cleanup_complete = false
      @import_run_count = 0
    end

    def prepared?
      !@import_result.nil?
    end

    def cleanup_complete?
      @cleanup_complete
    end

    def reference_root
      @importer_class::DEFAULT_REFERENCE_ROOT
    end

    def staged_root
      File.join(workspace_dir, 'mixed_sources')
    end

    def report_path
      import_result&.report_path
    end

    def prepare!
      return self if prepared?

      FileUtils.mkdir_p(temp_root)

      importer = @importer_class.new(
        output_dir: output_dir,
        workspace_dir: workspace_dir,
        keep_workspace: true,
        clean_output: true,
        maintain_directory_structure: true,
        emit_runtime_json: false,
        progress: @progress
      )

      resolved = importer.resolve_sources
      @importer = importer
      @resolved_source_paths_by_module_name = resolved.fetch(:module_files_by_name, {}).dup.freeze
      @selected_source_paths = Set.new(Array(resolved.fetch(:module_files)).map { |path| File.expand_path(path) }).freeze
      @resolved_include_dirs = Array(resolved.fetch(:include_dirs, [])).dup.freeze
      @dependency_graph = importer.send(:module_reference_graph, resolved.fetch(:module_files))
      @reference_module_files = reference_module_files(importer).freeze
      @reference_dependency_graph = importer.send(:module_reference_graph, @reference_module_files)
      @reference_source_paths_by_module_name = importer.send(:module_index, @reference_module_files)
                                                    .merge(@resolved_source_paths_by_module_name)
                                                    .freeze

      @import_result = importer.run
      @import_run_count += 1
      unless import_result.success?
        raise RuntimeError, "SPARC64 unit runtime import failed:\n#{diagnostic_summary(import_result)}"
      end

      closure_modules = Array(import_result.closure_modules)
      module_source_paths = import_result.module_files_by_name
      module_source_relpaths = import_result.module_source_relpaths

      if closure_modules.empty? || module_source_paths.nil? || module_source_paths.empty? || module_source_relpaths.nil? || module_source_relpaths.empty?
        closure_modules = Array(resolved.fetch(:closure_modules))
        module_source_paths = resolved.fetch(:module_files_by_name) do
          importer.send(:module_index, resolved.fetch(:module_files))
        end
        module_source_relpaths = resolved.fetch(:module_source_relpaths)
      end

      emitted_records = scan_emitted_ruby_records
      @emitted_ruby_records = emitted_records.freeze
      selected_records = select_source_backed_direct_emits(
        importer: importer,
        closure_modules: closure_modules,
        emitted_records: emitted_records,
        module_source_paths: module_source_paths,
        module_source_relpaths: module_source_relpaths,
        allowed_source_paths: @selected_source_paths
      )

      load_generated_tree!
      build_inventory(selected_records)
      self
    end

    def cleanup!
      return if cleanup_complete?

      FileUtils.rm_rf(temp_root) if Dir.exist?(temp_root)
      @cleanup_complete = true
    end

    def module_record(module_name)
      prepare!
      inventory_by_module_name.fetch(module_name.to_s)
    end

    def report_data
      prepare!
      @report_data ||= begin
        path = report_path
        path && File.file?(path) ? JSON.parse(File.read(path)) : {}
      end
    end

    def suite_raise_diagnostics
      prepare!
      @suite_raise_diagnostics ||= Array(report_data['raise_diagnostics']).freeze
    end

    def include_dirs
      prepare!
      Array(import_result&.include_dirs || @resolved_include_dirs).uniq.freeze
    end

    def staged_include_dirs
      prepare!

      Array(import_result&.staged_include_dirs || include_dirs.map { |dir| staged_path_for_source(dir) }).uniq.freeze
    end

    def staged_path_for_source(path)
      prepare!

      expanded_path = File.expand_path(path)
      expanded_reference_root = File.expand_path(reference_root)
      return expanded_path unless expanded_path.start_with?("#{expanded_reference_root}/")

      relative = relative_path(expanded_path, expanded_reference_root)
      File.join(staged_root, relative)
    end

    def dependency_verilog_files_for(module_name)
      prepare!
      requested = module_name.to_s
      return [] unless @dependency_graph

      closure = @importer.send(:module_closure, requested, @dependency_graph)
      closure.filter_map { |name| @resolved_source_paths_by_module_name[name] }.uniq.sort.freeze
    end

    def dependency_verilog_files_for_source(source_relative_path)
      prepare!

      modules = modules_for_source(source_relative_path)
      modules.flat_map { |record| dependency_verilog_files_for(record.module_name) }.uniq.sort.freeze
    end

    def parity_dependency_verilog_files_for(module_name)
      prepare!
      requested = module_name.to_s
      return dependency_verilog_files_for(requested) unless @reference_dependency_graph

      closure = @importer.send(:module_closure, requested, @reference_dependency_graph)
      closure.filter_map { |name| @reference_source_paths_by_module_name[name] }.uniq.sort.freeze
    end

    def parity_dependency_verilog_files_for_source(source_relative_path)
      prepare!

      modules = modules_for_source(source_relative_path)
      modules.flat_map { |record| parity_dependency_verilog_files_for(record.module_name) }.uniq.sort.freeze
    end

    def staged_dependency_verilog_files_for_source(source_relative_path)
      prepare!

      dependency_verilog_files_for_source(source_relative_path).map { |path| staged_path_for_source(path) }.uniq.sort.freeze
    end

    def modules_for_source(source_relative_path)
      prepare!
      inventory_by_source_relative_path.fetch(source_relative_path.to_s, [])
    end

    private

    EmittedRubyRecord = Struct.new(
      :class_name,
      :verilog_module_name,
      :generated_ruby_path,
      :generated_ruby_relative_path,
      keyword_init: true
    )

    def scan_emitted_ruby_records
      Dir.glob(File.join(output_dir, '**', '*.rb')).sort.filter_map do |path|
        source = File.read(path)
        class_name = source[/^\s*class\s+([A-Za-z_][A-Za-z0-9_:]*)\s*</, 1]
        verilog_module_name = source[/def self\.verilog_module_name\s+["']([^"']+)["']/m, 1]
        next unless class_name && verilog_module_name

        EmittedRubyRecord.new(
          class_name: class_name,
          verilog_module_name: verilog_module_name,
          generated_ruby_path: path,
          generated_ruby_relative_path: relative_path(path, output_dir)
        )
      end
    end

    def select_source_backed_direct_emits(importer:, closure_modules:, emitted_records:, module_source_paths:,
                                          module_source_relpaths:, allowed_source_paths:)
      emitted_by_module = emitted_records.group_by(&:verilog_module_name)

      Array(closure_modules).sort.filter_map do |module_name|
        next unless module_source_paths.key?(module_name)

        source_path = module_source_paths.fetch(module_name)
        next if allowed_source_paths && !allowed_source_paths.include?(File.expand_path(source_path))

        source_relative_path = module_source_relpaths.fetch(module_name) { importer.send(:source_relative_path, source_path) }
        expected_relpath = File.join(File.dirname(source_relative_path), "#{importer.send(:underscore_module_name, module_name)}.rb")
        candidates = Array(emitted_by_module[module_name])
        next if candidates.empty?

        record = candidates.find { |entry| entry.generated_ruby_relative_path == expected_relpath }
        record ||= candidates.find do |entry|
          File.basename(entry.generated_ruby_relative_path) == "#{importer.send(:underscore_module_name, module_name)}.rb"
        end
        next unless record

        {
          module_name: module_name,
          class_name: record.class_name,
          source_path: source_path,
          source_relative_path: source_relative_path,
          staged_source_path: File.join(staged_root, source_relative_path),
          generated_ruby_path: record.generated_ruby_path,
          generated_ruby_relative_path: record.generated_ruby_relative_path
        }
      end
    end

    def load_generated_tree!
      files = Dir.glob(File.join(output_dir, '**', '*.rb')).sort
      raise ArgumentError, "No generated Ruby HDL files found in #{output_dir}" if files.empty?

      clear_existing_generated_component_classes!(files)

      class_names_by_path = files.each_with_object({}) do |path, acc|
        acc[path] = generated_class_name_for_path(path)
      end
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
            remove_component_constant(class_names_by_path[path]) if class_names_by_path[path]
            still_pending << path
            last_errors[path] = e
          end
        end

        break if still_pending.empty?
        unless progressed
          details = still_pending.first(8).map do |path|
            "#{relative_path(path, output_dir)}: #{last_errors[path].message}"
          end.join("\n")
          raise RuntimeError, "Unable to resolve generated SPARC64 HDL tree:\n#{details}"
        end

        pending = still_pending
      end
    end

    def generated_class_name_for_path(path)
      File.read(path)[/^\s*class\s+([A-Za-z_][A-Za-z0-9_:]*)\s*</, 1]
    end

    def clear_existing_generated_component_classes!(files)
      files.each do |path|
        source = File.read(path)
        class_name = source[/^\s*class\s+([A-Za-z_][A-Za-z0-9_:]*)\s*</, 1]
        next unless class_name

        remove_component_constant(class_name)
      end
    end

    def remove_component_constant(constant_path)
      names = constant_path.to_s.split('::')
      return if names.empty?

      scope = Object
      *parents, leaf = names

      parents.each do |name|
        break unless scope.const_defined?(name, false)
        value = scope.const_get(name, false)
        return unless value.is_a?(Module)
        scope = value
      end

      scope.send(:remove_const, leaf.to_sym) if scope.const_defined?(leaf, false)
    rescue NameError
      nil
    end

    def build_inventory(selected_records)
      records = selected_records.map do |entry|
        ModuleRecord.new(
          module_name: entry.fetch(:module_name),
          class_name: entry.fetch(:class_name),
          component_class: constantize(entry.fetch(:class_name)),
          source_path: entry.fetch(:source_path),
          source_relative_path: entry.fetch(:source_relative_path),
          staged_source_path: entry.fetch(:staged_source_path),
          generated_ruby_path: entry.fetch(:generated_ruby_path),
          generated_ruby_relative_path: entry.fetch(:generated_ruby_relative_path)
        )
      end.sort_by(&:module_name)

      @inventory_records = records.freeze
      @inventory_by_module_name = records.each_with_object({}) { |record, acc| acc[record.module_name] = record }.freeze
      @inventory_by_source_relative_path = records.group_by(&:source_relative_path)
                                            .transform_values { |items| items.sort_by(&:module_name).freeze }
                                            .freeze
    end

    def constantize(class_name)
      class_name.to_s.split('::').inject(Object) do |scope, name|
        scope.const_get(name, false)
      end
    end

    def relative_path(path, base)
      Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(File.expand_path(base))).to_s
    end

    def reference_module_files(importer)
      Dir.glob(File.join(reference_root, '**', '*')).sort.select do |path|
        File.file?(path) &&
          importer.send(:verilog_source_file?, path) &&
          importer.send(:module_defining_verilog_file?, path)
      end
    end

    def diagnostic_summary(result)
      lines = []
      lines.concat(Array(result.diagnostics)) if result.respond_to?(:diagnostics)
      Array(result.raise_diagnostics).each do |diag|
        if diag.respond_to?(:message)
          op = diag.respond_to?(:op) && diag.op ? " #{diag.op}:" : ''
          lines << "[#{diag.respond_to?(:severity) ? diag.severity : 'error'}]#{op} #{diag.message}"
        else
          lines << diag.to_s
        end
      end
      lines.join("\n")
    end
  end

  module RuntimeImportRequirements
    module_function

    def require_reference_tree!(importer_class = RHDL::Examples::SPARC64::Import::SystemImporter)
      skip 'SPARC64 reference tree not available' unless Dir.exist?(importer_class::DEFAULT_REFERENCE_ROOT)
      skip 'SPARC64 top source file not available' unless File.file?(importer_class::DEFAULT_TOP_FILE)
    end

    def require_import_tool!
      tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
      skip "#{tool} not available" unless HdlToolchain.which(tool)
      skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    end
  end
end

RSpec.configure do |config|
  config.after(:suite) do
    Sparc64UnitSupport::RuntimeImportSession.cleanup_current!
  end
end
