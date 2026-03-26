# frozen_string_literal: true

module RHDL
  module Examples
    module SPARC64
      module Tasks
        class ImportTask
          attr_reader :options

          def initialize(options = {})
            @options = options
          end

          def run
            importer = importer_class.new(
              reference_root: options[:reference_root] || importer_class::DEFAULT_REFERENCE_ROOT,
              top: options[:top] || importer_class::DEFAULT_TOP,
              top_file: options[:top_file] || importer_class::DEFAULT_TOP_FILE,
              output_dir: options[:output_dir] || importer_class::DEFAULT_OUTPUT_DIR,
              workspace_dir: options[:workspace_dir],
              keep_workspace: options.fetch(:keep_workspace, false),
              clean_output: options.fetch(:clean_output, true),
              maintain_directory_structure: options.fetch(:maintain_directory_structure, true),
              strict: options.fetch(:strict, true),
              progress: options[:progress]
            )

            result = importer.run

            puts "SPARC64 import success=#{result.success?} files=#{Array(result.files_written).length}"
            puts "SPARC64 import output=#{result.output_dir}" if result.respond_to?(:output_dir) && result.output_dir
            puts "SPARC64 import workspace=#{result.workspace}" if result.respond_to?(:workspace) && result.workspace
            puts "SPARC64 import manifest=#{result.manifest_path}" if result.respond_to?(:manifest_path) && result.manifest_path
            puts "SPARC64 import report=#{result.report_path}" if result.respond_to?(:report_path) && result.report_path

            diagnostics = Array(result.diagnostics) + Array(result.raise_diagnostics).map do |diag|
              if diag.respond_to?(:message)
                "[#{diag.respond_to?(:severity) ? diag.severity : 'warning'}] #{diag.message}"
              else
                diag.to_s
              end
            end

            if result.success?
              diagnostics.first(10).each { |line| puts line }
              omitted = diagnostics.length - 10
              puts "SPARC64 import diagnostics omitted=#{omitted}" if omitted.positive?
              return
            end

            diagnostics.each { |line| puts line }
            raise RuntimeError, 'SPARC64 import failed'
          end

          private

          def importer_class
            return options[:importer_class] if options[:importer_class]

            require_relative '../import/system_importer'
            RHDL::Examples::SPARC64::Import::SystemImporter
          end
        end
      end
    end
  end
end
