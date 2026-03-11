# frozen_string_literal: true

require 'optparse'

project_root = File.expand_path('../../..', __dir__)
$LOAD_PATH.unshift(File.expand_path('../../../lib', __dir__)) unless $LOAD_PATH.include?(File.expand_path('../../../lib', __dir__))
$LOAD_PATH.unshift(project_root) unless $LOAD_PATH.include?(project_root)

require 'rhdl'
require_relative 'tasks/import_task'
require_relative 'tasks/parity_task'
require_relative 'tasks/verify_task'
require 'rhdl/cli/tasks/ao486_task'

module RHDL
  module Examples
    module AO486
      module CLI
        module_function

        PUBLIC_RUN_MODES = %i[ir verilog circt].freeze
        RUN_MODE_ALIASES = {
          'ir' => :ir,
          'verilog' => :verilog,
          'verilator' => :verilog,
          'circt' => :circt,
          'arcilator' => :circt
        }.freeze
        RUN_SIM_ALIASES = {
          'interpret' => :interpret,
          'jit' => :jit,
          'compile' => :compile,
          'compiler' => :compile
        }.freeze

        def show_help(out:, program_name:)
          out.puts <<~HELP
            Usage: #{program_name} [options]
                   #{program_name} <subcommand> [options]

            AO486 CPU-top runner and CIRCT import/parity workflow.

              Default mode:
                Running without a subcommand starts the AO486 runner.

              Run options:
                -m, --mode ir|verilog|circt
                --sim interpret|jit|compile
                --bios
                --dos
                --headless
                --cycles N
                -s, --speed CYCLES
                -d, --debug

              Subcommands:
                import       Import rtl/ao486/ao486.v via CIRCT and raise DSL output
                parity       Run bounded Verilog (Verilator) vs raised RHDL parity harness
                verify       Run AO486 importer + parity + import-path verification specs

              Examples:
                #{program_name} --bios --dos
                #{program_name} -m verilog --bios --dos --headless --cycles 100000
                #{program_name} -m circt --bios --dos -d -s 5000
                #{program_name} import --out examples/ao486/import
                #{program_name} parity
                #{program_name} verify
          HELP
        end

        def normalize_run_mode(value)
          mode = RUN_MODE_ALIASES[value.to_s.strip.downcase]
          raise OptionParser::InvalidArgument, value if mode.nil?

          mode
        end

        def normalize_run_sim(value)
          sim = RUN_SIM_ALIASES[value.to_s.strip.downcase]
          raise OptionParser::InvalidArgument, value if sim.nil?

          sim
        end

        def run(argv = ARGV,
                out: $stdout,
                err: $stderr,
                run_task_class: RHDL::CLI::Tasks::AO486Task,
                import_task_class: RHDL::Examples::AO486::Tasks::ImportTask,
                parity_task_class: RHDL::Examples::AO486::Tasks::ParityTask,
                verify_task_class: RHDL::Examples::AO486::Tasks::VerifyTask,
                program_name: 'rhdl examples ao486')
          args = argv.dup
          subcommand = args.first

          case subcommand
          when 'import'
            args.shift
            run_import(
              args,
              out: out,
              err: err,
              task_class: import_task_class,
              program_name: program_name
            )
          when 'parity'
            args.shift
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
            args.shift
            run_simple_subcommand(
              args,
              out: out,
              err: err,
              task_class: verify_task_class,
              program_name: program_name,
              subcommand: 'verify',
              description: 'Run AO486 verification suite: importer spec + parity spec + CIRCT import-path spec.'
            )
          when '-h', '--help', 'help'
            show_help(out: out, program_name: program_name)
            0
          else
            run_default(
              args,
              out: out,
              err: err,
              task_class: run_task_class,
              program_name: program_name
            )
          end
        rescue StandardError => e
          err.puts e.message
          1
        end

        def run_default(args, out:, err:, task_class:, program_name:)
          options = {
            action: :run,
            mode: :ir,
            sim: :compile,
            bios: false,
            dos: false,
            debug: false,
            headless: false,
            cycles: nil,
            speed: nil,
            help: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = <<~BANNER
              Usage: #{program_name} [options]

              Run the AO486 CPU-top environment.

              Options:
            BANNER

            opts.on('-m', '--mode TYPE', String,
                    'Simulation mode: ir (default), verilog, circt') do |v|
              options[:mode] = normalize_run_mode(v)
            end
            opts.on('--sim TYPE', String,
                    'IR simulator backend: compile (default), interpret, jit') do |v|
              options[:sim] = normalize_run_sim(v)
            end
            opts.on('--bios', 'Load BIOS ROMs from examples/ao486/software/rom') do
              options[:bios] = true
            end
            opts.on('--dos', 'Load DOS floppy image from examples/ao486/software/bin') do
              options[:dos] = true
            end
            opts.on('--headless', 'Run once without the interactive terminal loop') do
              options[:headless] = true
            end
            opts.on('--cycles N', Integer, 'Headless cycle count override (defaults to unlimited)') do |v|
              options[:cycles] = v
            end
            opts.on('-s', '--speed CYCLES', Integer, 'Cycles per frame/chunk (defaults to unlimited)') do |v|
              options[:speed] = v
            end
            opts.on('-d', '--debug', 'Show debug info below the display') do
              options[:debug] = true
            end
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

        def run_import(args, out:, err:, task_class:, program_name:)
          options = {
            source_path: nil,
            output_dir: nil,
            workspace_dir: nil,
            top: nil,
            import_strategy: RHDL::CLI::Tasks::AO486Task::DEFAULT_CLI_IMPORT_STRATEGY,
            fallback_to_stubbed: false,
            maintain_directory_structure: true,
            format_output: false,
            keep_workspace: false,
            clean_output: true,
            strict: false,
            report: nil,
            help: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = <<~BANNER
              Usage: #{program_name} import [options]

              Import AO486 `rtl/ao486/ao486.v` via CIRCT and raise RHDL DSL.

              Options:
            BANNER

            opts.on('--source FILE', 'Override source Verilog path (default: examples/ao486/reference/rtl/ao486/ao486.v)') do |v|
              options[:source_path] = v
            end
            opts.on('--out DIR', 'Output directory for raised DSL (required)') { |v| options[:output_dir] = v }
            opts.on('--workspace DIR', 'Workspace directory for intermediate artifacts') { |v| options[:workspace_dir] = v }
            opts.on('--report FILE', 'Write AO486 import report JSON to FILE') { |v| options[:report] = v }
            opts.on('--top NAME', 'Top module name override (default: ao486)') { |v| options[:top] = v }
            opts.on('--strategy STRATEGY', %i[stubbed tree],
                    'Import strategy: tree (default) or stubbed (force top-level baseline)') do |v|
              options[:import_strategy] = v
            end
            opts.on('--[no-]fallback',
                    'Tree strategy: fallback to stubbed strategy if tree import fails (default: false)') do |v|
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
                    'Treat importer/raise issues as failures and keep AO486 strict gate enabled (default: false)') do |v|
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
