# frozen_string_literal: true

require 'optparse'

project_root = File.expand_path('../../..', __dir__)
$LOAD_PATH.unshift(File.expand_path('../../../lib', __dir__)) unless $LOAD_PATH.include?(File.expand_path('../../../lib', __dir__))
$LOAD_PATH.unshift(project_root) unless $LOAD_PATH.include?(project_root)

require 'rhdl'
require_relative 'tasks/import_task'
require_relative 'tasks/parity_task'
require_relative 'tasks/verify_task'

module RHDL
  module Examples
    module AO486
      module CLI
        module_function

        def show_help(out:, program_name:)
          out.puts <<~HELP
            Usage: #{program_name} <subcommand> [options]

            AO486 CIRCT import/parity workflow.

              Subcommands:
                import       Import rtl/system.v via CIRCT and raise DSL output
                parity       Run bounded Verilog (Verilator) vs raised RHDL parity harness
                verify       Run AO486 importer + parity + import-path verification specs

              Examples:
                #{program_name} import --out examples/ao486/hdl
                #{program_name} import --out examples/ao486/hdl --strategy stubbed
                #{program_name} import --out examples/ao486/hdl --workspace tmp/ao486_ws --keep-workspace
                #{program_name} parity
                #{program_name} verify

            Run '#{program_name} <subcommand> --help' for more information.
          HELP
        end

        def run(argv = ARGV,
                out: $stdout,
                err: $stderr,
                import_task_class: RHDL::Examples::AO486::Tasks::ImportTask,
                parity_task_class: RHDL::Examples::AO486::Tasks::ParityTask,
                verify_task_class: RHDL::Examples::AO486::Tasks::VerifyTask,
                program_name: 'rhdl examples ao486')
          args = argv.dup
          subcommand = args.shift

          case subcommand
          when 'import'
            run_import(
              args,
              out: out,
              err: err,
              task_class: import_task_class,
              program_name: program_name
            )
          when 'parity'
            run_simple_subcommand(
              args,
              out: out,
              err: err,
              task_class: parity_task_class,
              program_name: program_name,
              subcommand: 'parity',
              description: 'Run the AO486 bounded parity harness: source Verilog (Verilator) vs raised RHDL (available IR backends).'
            )
          when 'verify'
            run_simple_subcommand(
              args,
              out: out,
              err: err,
              task_class: verify_task_class,
              program_name: program_name,
              subcommand: 'verify',
              description: 'Run AO486 verification suite: importer spec + parity spec + CIRCT import-path spec.'
            )
          when '-h', '--help', 'help', nil
            show_help(out: out, program_name: program_name)
            0
          else
            err.puts "Unknown examples ao486 subcommand: #{subcommand}"
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
            source_path: nil,
            output_dir: nil,
            workspace_dir: nil,
            top: nil,
            import_strategy: RHDL::CLI::Tasks::AO486Task::DEFAULT_CLI_IMPORT_STRATEGY,
            fallback_to_stubbed: true,
            maintain_directory_structure: true,
            format_output: false,
            keep_workspace: false,
            clean_output: true,
            strict: true,
            report: nil,
            help: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = <<~BANNER
              Usage: #{program_name} import [options]

              Import AO486 `rtl/system.v` via CIRCT and raise RHDL DSL.

              Options:
            BANNER

            opts.on('--source FILE', 'Override source Verilog path (default: examples/ao486/reference/rtl/system.v)') do |v|
              options[:source_path] = v
            end
            opts.on('--out DIR', 'Output directory for raised DSL (required)') { |v| options[:output_dir] = v }
            opts.on('--workspace DIR', 'Workspace directory for intermediate artifacts') { |v| options[:workspace_dir] = v }
            opts.on('--report FILE', 'Write AO486 import report JSON to FILE') { |v| options[:report] = v }
            opts.on('--top NAME', 'Top module name override (default: system)') { |v| options[:top] = v }
            opts.on('--strategy STRATEGY', %i[stubbed tree],
                    'Import strategy: tree (default) or stubbed (force top-level baseline)') do |v|
              options[:import_strategy] = v
            end
            opts.on('--[no-]fallback',
                    'Tree strategy: fallback to stubbed strategy if tree import fails (default: true)') do |v|
              options[:fallback_to_stubbed] = v
            end
            opts.on('--[no-]keep-structure',
                    'Keep source Verilog directories in output DSL paths (default: true)') do |v|
              options[:maintain_directory_structure] = v
            end
            opts.on('--[no-]format',
                    'Format raised RHDL output with RuboCop after import (default: false)') do |v|
              options[:format_output] = v
            end
            opts.on('--[no-]strict',
                    'Treat importer/raise issues as failures and keep AO486 strict gate enabled (default: true)') do |v|
              options[:strict] = v
            end
            opts.on('--keep-workspace', 'Keep workspace artifacts after run') { options[:keep_workspace] = true }
            opts.on('--[no-]clean', '--[no-]clean-output',
                    'Clean output directory contents before write (default: true)') do |v|
              options[:clean_output] = v
            end
            opts.on('-h', '--help', 'Show this help') do
              out.puts opts
              options[:help] = true
            end
          end

          parser.parse!(args)
          return 0 if options[:help]

          if options[:output_dir].to_s.strip.empty?
            err.puts 'Missing required option: --out DIR'
            err.puts
            err.puts parser
            return 1
          end

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

        def run_simple_subcommand(args, out:, err:, task_class:, program_name:, subcommand:, description:)
          options = { help: false }

          parser = OptionParser.new do |opts|
            opts.banner = <<~BANNER
              Usage: #{program_name} #{subcommand} [options]

              #{description}

              Options:
            BANNER

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

          task_class.new.run
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
