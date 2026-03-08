# frozen_string_literal: true

require 'optparse'

project_root = File.expand_path('../../..', __dir__)
$LOAD_PATH.unshift(File.expand_path('../../../lib', __dir__)) unless $LOAD_PATH.include?(File.expand_path('../../../lib', __dir__))
$LOAD_PATH.unshift(project_root) unless $LOAD_PATH.include?(project_root)

require 'rhdl'
require_relative 'import/system_importer'
require_relative 'tasks/import_task'

module RHDL
  module Examples
    module SPARC64
      module CLI
        module_function

        def show_help(out:, program_name:)
          out.puts <<~HELP
            Usage: #{program_name} <subcommand> [options]

            SPARC64 CIRCT import workflow.

              Subcommands:
                import       Import the SPARC64 reference design and raise RHDL DSL

              Examples:
                #{program_name} import
                #{program_name} import --out examples/sparc64/import
                #{program_name} import --workspace tmp/sparc64_ws --keep-workspace

            Run '#{program_name} <subcommand> --help' for more information.
          HELP
        end

        def run(argv = ARGV,
                out: $stdout,
                err: $stderr,
                import_task_class: RHDL::Examples::SPARC64::Tasks::ImportTask,
                program_name: 'rhdl examples sparc64')
          args = argv.dup
          subcommand = args.shift

          case subcommand
          when 'import'
            run_import(args, out: out, err: err, task_class: import_task_class, program_name: program_name)
          when '-h', '--help', 'help', nil
            show_help(out: out, program_name: program_name)
            0
          else
            err.puts "Unknown examples sparc64 subcommand: #{subcommand}"
            err.puts
            show_help(out: err, program_name: program_name)
            1
          end
        rescue StandardError => e
          err.puts e.message
          1
        end

        def run_import(args, out:, err:, task_class:, program_name:)
          options = {
            output_dir: RHDL::Examples::SPARC64::Import::SystemImporter::DEFAULT_OUTPUT_DIR,
            workspace_dir: nil,
            reference_root: nil,
            top: nil,
            top_file: nil,
            maintain_directory_structure: true,
            keep_workspace: false,
            clean_output: true,
            strict: true,
            help: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = <<~BANNER
              Usage: #{program_name} import [options]

              Import the SPARC64 reference design into raised RHDL.

              Options:
            BANNER

            opts.on('--out DIR',
                    "Output directory for raised DSL (default: #{RHDL::Examples::SPARC64::Import::SystemImporter::DEFAULT_OUTPUT_DIR})") do |v|
              options[:output_dir] = v
            end
            opts.on('--workspace DIR', 'Workspace directory for intermediate artifacts') { |v| options[:workspace_dir] = v }
            opts.on('--reference-root DIR', 'Override the SPARC64 reference tree root') { |v| options[:reference_root] = v }
            opts.on('--top NAME', "Top module name override (default: #{RHDL::Examples::SPARC64::Import::SystemImporter::DEFAULT_TOP})") do |v|
              options[:top] = v
            end
            opts.on('--top-file FILE', "Top source file override (default: #{RHDL::Examples::SPARC64::Import::SystemImporter::DEFAULT_TOP_FILE})") do |v|
              options[:top_file] = v
            end
            opts.on('--[no-]keep-structure',
                    'Keep the raised RHDL output in the source directory structure (default: true)') do |v|
              options[:maintain_directory_structure] = v
            end
            opts.on('--keep-workspace', 'Keep workspace artifacts after import') { options[:keep_workspace] = true }
            opts.on('--[no-]clean', '--[no-]clean-output',
                    'Clean output directory contents before write (default: true)') do |v|
              options[:clean_output] = v
            end
            opts.on('--[no-]strict', 'Treat import issues as failures (default: true)') { |v| options[:strict] = v }
            opts.on('-h', '--help', 'Show this help') do
              out.puts opts
              options[:help] = true
            end
          end

          parser.parse!(args)
          return 0 if options[:help]

          unless args.empty?
            err.puts "Unexpected arguments: #{args.join(' ')}"
            err.puts
            err.puts parser
            return 1
          end

          task_class.new(options).run
          0
        rescue OptionParser::ParseError => e
          err.puts "Error: #{e.message}"
          err.puts
          err.puts parser
          1
        end
      end
    end
  end
end
