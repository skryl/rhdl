# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'set'
require 'tmpdir'

require_relative '../../../examples/ao486/utilities/import/cpu_importer'

module AO486UnitSupport
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
      :raised_ruby_source,
      :component_namespace,
      keyword_init: true
    )

    EmittedRubyRecord = Struct.new(
      :class_name,
      :verilog_module_name,
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
                :emitted_ruby_records, :source_result, :component_result, :component_namespace

    def initialize(importer_class: RHDL::Examples::AO486::Import::CpuImporter,
                   temp_root: nil,
                   progress: nil)
      @importer_class = importer_class
      @temp_root = File.expand_path(temp_root || Dir.mktmpdir('rhdl_ao486_unit_suite'))
      @output_dir = File.join(@temp_root, 'output')
      @workspace_dir = File.join(@temp_root, 'workspace')
      @progress = progress || ->(_message) {}
      @inventory_records = []
      @inventory_by_module_name = {}
      @inventory_by_source_relative_path = {}
      @emitted_ruby_records = []
      @cleanup_complete = false
      @import_run_count = 0
      @dependency_cache = {}
      @suite_raise_diagnostics = nil
      @raised_sources_by_module_name = {}
      @raised_components_by_module_name = {}
    end

    def prepared?
      !@import_result.nil?
    end

    def cleanup_complete?
      @cleanup_complete
    end

    def reference_root
      if @importer_class.const_defined?(:DEFAULT_SOURCE_ROOT, false)
        File.expand_path(@importer_class.const_get(:DEFAULT_SOURCE_ROOT, false))
      else
        File.expand_path(File.dirname(@importer_class::DEFAULT_SOURCE_PATH))
      end
    end

    def suite_raise_diagnostics
      prepare!
      Array(@suite_raise_diagnostics).freeze
    end

    def include_dirs
      prepare!
      Array(import_result.include_dirs).uniq.freeze
    end

    def staged_include_dirs
      prepare!
      Array(import_result.staged_include_dirs).uniq.freeze
    end

    def closure_modules
      prepare!
      Array(import_result.closure_modules).uniq.sort.freeze
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
        strict: false,
        progress: @progress
      )

      @importer = importer
      @import_result = importer.run
      @import_run_count += 1
      unless import_result.success?
        raise RuntimeError, "AO486 CPU unit runtime import failed:\n#{diagnostic_summary(import_result)}"
      end

      @module_files_by_name = Hash(import_result.module_files_by_name).transform_keys(&:to_s).freeze
      @staged_module_files_by_name = Hash(import_result.staged_module_files_by_name).transform_keys(&:to_s).freeze
      @module_source_relpaths = Hash(import_result.module_source_relpaths).transform_keys(&:to_s).freeze
      @closure_modules = Array(import_result.closure_modules).map(&:to_s).uniq.sort.freeze

      module_to_file, module_to_body = importer.send(:build_module_index, reference_root)
      @module_to_file = module_to_file.transform_keys(&:to_s).freeze
      @module_to_body = module_to_body.transform_keys(&:to_s).freeze
      @dependency_graph = build_dependency_graph(@closure_modules).freeze

      load_raised_results!

      emitted_records = scan_emitted_ruby_records
      @emitted_ruby_records = emitted_records.freeze
      selected_records = select_source_backed_direct_emits(
        importer: importer,
        closure_modules: @closure_modules,
        emitted_records: emitted_records,
        module_source_paths: @module_files_by_name,
        module_source_relpaths: @module_source_relpaths
      )

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

    def records_for_source(source_relative_path)
      prepare!
      inventory_by_source_relative_path.fetch(source_relative_path.to_s)
    end

    def dependency_verilog_files_for_source(source_relative_path)
      prepare!

      module_names = records_for_source(source_relative_path).map(&:module_name)
      closure = dependency_closure(module_names)
      source_paths = records_for_source(source_relative_path).map(&:source_path).map { |path| File.expand_path(path) }.to_set
      closure.filter_map do |module_name|
        path = @module_files_by_name[module_name]
        next unless path

        expanded = File.expand_path(path)
        next if source_paths.include?(expanded)

        expanded
      end.uniq.sort
    end

    def staged_dependency_verilog_files_for_source(source_relative_path)
      prepare!

      module_names = records_for_source(source_relative_path).map(&:module_name)
      source_paths = records_for_source(source_relative_path).map(&:staged_source_path).map { |path| File.expand_path(path) }.to_set
      dependency_closure(module_names).filter_map do |module_name|
        path = @staged_module_files_by_name[module_name]
        next unless path

        expanded = File.expand_path(path)
        next if source_paths.include?(expanded)

        expanded
      end.uniq.sort
    end

    private

    def build_dependency_graph(module_names)
      allowed = module_names.to_set
      module_names.each_with_object({}) do |module_name, acc|
        body = @module_to_body[module_name]
        deps = body ? @importer.send(:extract_instantiated_modules, body).map(&:to_s) : []
        acc[module_name] = deps.select { |child| allowed.include?(child) }.uniq.sort.freeze
      end
    end

    def dependency_closure(module_names)
      key = Array(module_names).map(&:to_s).sort.freeze
      @dependency_cache[key] ||= begin
        seen = Set.new
        queue = key.dup

        until queue.empty?
          module_name = queue.shift
          next if seen.include?(module_name)

          seen << module_name
          queue.concat(Array(@dependency_graph[module_name]))
        end

        seen.to_a.sort.freeze
      end
    end

    def load_raised_results!
      mlir_path = import_result.normalized_core_mlir_path
      raise ArgumentError, "Missing normalized AO486 CPU MLIR at #{mlir_path}" unless File.file?(mlir_path)

      normalized_core_mlir = File.read(mlir_path)
      @source_result = RHDL::Codegen::CIRCT::Raise.to_sources(
        normalized_core_mlir,
        top: @importer.top,
        strict: false
      )
      @component_namespace = Module.new
      @component_result = RHDL::Codegen::CIRCT::Raise.to_components(
        normalized_core_mlir,
        namespace: @component_namespace,
        top: @importer.top,
        strict: false
      )
      @suite_raise_diagnostics = merge_diagnostics(
        import_result.raise_diagnostics,
        source_result.diagnostics,
        component_result.diagnostics
      ).freeze

      unless source_result.success? && component_result.success?
        raise RuntimeError, "AO486 CPU unit in-memory raise failed:\n#{diagnostic_summary(source_result, component_result)}"
      end

      @raised_sources_by_module_name = Hash(source_result.sources).transform_keys(&:to_s).freeze
      @raised_components_by_module_name = Hash(component_result.components).transform_keys(&:to_s).freeze
    end

    def scan_emitted_ruby_records
      Dir.glob(File.join(output_dir, '**', '*.rb')).sort.filter_map do |path|
        source = File.read(path)
        class_name = source[/^\s*class\s+([A-Za-z_][A-Za-z0-9_:]*)\s*</, 1]
        verilog_module_name = source[/def self\.verilog_module_name\s+['"]([^'"]+)['"]/m, 1]
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
                                          module_source_relpaths:)
      emitted_by_module = emitted_records.group_by(&:verilog_module_name)

      Array(closure_modules).sort.filter_map do |module_name|
        source_path = module_source_paths[module_name]
        next unless source_path

        source_relative_path = module_source_relpaths.fetch(module_name) do
          importer.send(:source_relative_path, source_path)
        end
        expected_relpath = File.join(
          File.dirname(source_relative_path),
          "#{importer.send(:underscore_module_name, module_name)}.rb"
        )

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
          staged_source_path: @staged_module_files_by_name.fetch(module_name),
          generated_ruby_path: record.generated_ruby_path,
          generated_ruby_relative_path: record.generated_ruby_relative_path
        }
      end
    end

    def build_inventory(selected_records)
      records = selected_records.map do |entry|
        module_name = entry.fetch(:module_name)

        ModuleRecord.new(
          module_name: module_name,
          class_name: entry.fetch(:class_name),
          component_class: @raised_components_by_module_name.fetch(module_name),
          source_path: entry.fetch(:source_path),
          source_relative_path: entry.fetch(:source_relative_path),
          staged_source_path: entry.fetch(:staged_source_path),
          generated_ruby_path: entry.fetch(:generated_ruby_path),
          generated_ruby_relative_path: entry.fetch(:generated_ruby_relative_path),
          raised_ruby_source: @raised_sources_by_module_name.fetch(module_name),
          component_namespace: component_namespace
        )
      end.sort_by(&:module_name)

      @inventory_records = records.freeze
      @inventory_by_module_name = records.each_with_object({}) { |record, acc| acc[record.module_name] = record }.freeze
      @inventory_by_source_relative_path = records.group_by(&:source_relative_path)
                                            .transform_values { |items| items.sort_by(&:module_name).freeze }
                                            .freeze
    end

    def merge_diagnostics(*collections)
      collections.flatten.compact.each_with_object([]) do |diag, acc|
        key = diagnostic_key(diag)
        next if acc.any? { |existing| diagnostic_key(existing) == key }

        acc << diag
      end
    end

    def diagnostic_key(diag)
      if diag.respond_to?(:severity) || diag.respond_to?(:message) || diag.respond_to?(:op)
        [diag.respond_to?(:severity) ? diag.severity.to_s : nil,
         diag.respond_to?(:op) ? diag.op.to_s : nil,
         diag.respond_to?(:message) ? diag.message.to_s : diag.to_s]
      else
        diag.to_s
      end
    end

    def relative_path(path, base)
      Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(File.expand_path(base))).to_s
    end

    def diagnostic_summary(*results)
      lines = results.flatten.compact.flat_map do |result|
        if result.respond_to?(:diagnostics)
          Array(result.diagnostics)
        elsif result.respond_to?(:raise_diagnostics)
          Array(result.raise_diagnostics)
        else
          Array(result)
        end
      end.map do |diag|
        if diag.respond_to?(:message)
          op = diag.respond_to?(:op) && diag.op ? " #{diag.op}:" : ''
          "[#{diag.respond_to?(:severity) ? diag.severity : 'error'}]#{op} #{diag.message}"
        else
          diag.to_s
        end
      end

      lines.join("\n")
    end
  end

  module RuntimeImportRequirements
    module_function

    def require_reference_tree!(importer_class = RHDL::Examples::AO486::Import::CpuImporter)
      source_root = if importer_class.const_defined?(:DEFAULT_SOURCE_ROOT, false)
                      importer_class.const_get(:DEFAULT_SOURCE_ROOT, false)
                    else
                      File.dirname(importer_class::DEFAULT_SOURCE_PATH)
                    end
      skip 'AO486 reference tree not available' unless Dir.exist?(source_root)
      skip 'AO486 CPU top source not available' unless File.file?(importer_class::DEFAULT_SOURCE_PATH)
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
    AO486UnitSupport::RuntimeImportSession.cleanup_current!
  end
end
