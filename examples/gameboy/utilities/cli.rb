# frozen_string_literal: true

require 'optparse'

project_root = File.expand_path('../../..', __dir__)
$LOAD_PATH.unshift(File.expand_path('../../../lib', __dir__)) unless $LOAD_PATH.include?(File.expand_path('../../../lib', __dir__))
$LOAD_PATH.unshift(project_root) unless $LOAD_PATH.include?(project_root)

require 'rhdl'
require_relative 'tasks/run_task'
require_relative 'import/system_importer'

module RHDL
  module Examples
    module GameBoy
      module CLI
        module_function

        def run(argv = ARGV,
                out: $stdout,
                err: $stderr,
                run_task_class: RHDL::Examples::GameBoy::Tasks::RunTask,
                importer_class: RHDL::Examples::GameBoy::Import::SystemImporter,
                program_name: 'bin/gb')
          args = argv.dup

          return run_import(args.drop(1), out: out, err: err, importer_class: importer_class, program_name: program_name) if args.first == 'import'

          run_emulator(args, out: out, err: err, run_task_class: run_task_class, program_name: program_name)
        rescue Interrupt
          out.puts "\nInterrupted."
          0
        rescue StandardError => e
          err.puts "Error: #{e.message}"
          1
        end

        def run_import(args, out:, err:, importer_class:, program_name:)
          default_output_dir = importer_constant(importer_class, :DEFAULT_OUTPUT_DIR,
                                                 RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_OUTPUT_DIR)
          default_top = importer_constant(importer_class, :DEFAULT_TOP,
                                          RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_TOP)
          default_top_file = importer_constant(importer_class, :DEFAULT_TOP_FILE,
                                               RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_TOP_FILE)
          default_import_strategy = importer_constant(
            importer_class,
            :DEFAULT_IMPORT_STRATEGY,
            RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_IMPORT_STRATEGY
          )
          valid_import_strategies = importer_constant(
            importer_class,
            :VALID_IMPORT_STRATEGIES,
            RHDL::Examples::GameBoy::Import::SystemImporter::VALID_IMPORT_STRATEGIES
          )

          options = {
            output_dir: default_output_dir,
            workspace_dir: nil,
            reference_root: nil,
            qip_path: nil,
            top: nil,
            top_file: nil,
            import_strategy: default_import_strategy,
            maintain_directory_structure: true,
            keep_workspace: false,
            clean_output: true,
            strict: true,
            help: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = <<~BANNER
              Usage: #{program_name} import [options]

              Import the Game Boy reference design into raised RHDL.

              Options:
            BANNER

            opts.on('--out DIR',
                    "Output directory for raised DSL (default: #{default_output_dir})") do |v|
              options[:output_dir] = v
            end
            opts.on('--workspace DIR', 'Workspace directory for intermediate artifacts') { |v| options[:workspace_dir] = v }
            opts.on('--reference-root DIR', 'Override the Game Boy reference tree root') { |v| options[:reference_root] = v }
            opts.on('--qip FILE', 'Override the Quartus QIP manifest path') { |v| options[:qip_path] = v }
            opts.on('--top NAME', "Top module name override (default: #{default_top})") { |v| options[:top] = v }
            opts.on('--top-file FILE', "Top source file override (default: #{default_top_file})") do |v|
              options[:top_file] = v
            end
            opts.on('--strategy STRATEGY', valid_import_strategies,
                    "Import strategy (default: #{default_import_strategy})") do |v|
              options[:import_strategy] = v
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

          importer_options = {
            output_dir: expand_path(options[:output_dir]),
            workspace_dir: expand_path(options[:workspace_dir]),
            keep_workspace: options[:keep_workspace],
            clean_output: options[:clean_output],
            maintain_directory_structure: options[:maintain_directory_structure],
            strict: options[:strict],
            import_strategy: options[:import_strategy],
            progress: ->(message) { out.puts("GameBoy import step: #{message}") }
          }
          importer_options[:reference_root] = expand_path(options[:reference_root]) if options[:reference_root]
          importer_options[:qip_path] = expand_path(options[:qip_path]) if options[:qip_path]
          importer_options[:top] = options[:top] if options[:top]
          importer_options[:top_file] = expand_path(options[:top_file]) if options[:top_file]

          result = importer_class.new(**importer_options).run
          return handle_import_failure(result, err: err) unless result.success?

          out.puts "Imported Game Boy reference design to #{result.output_dir}"
          out.puts "Report: #{result.report_path}" if result.respond_to?(:report_path) && result.report_path
          0
        rescue OptionParser::ParseError => e
          err.puts "Error: #{e.message}"
          err.puts
          err.puts parser
          1
        end

        def run_emulator(args, out:, err:, run_task_class:, program_name:)
          options = {
            speed: 100,
            debug: false,
            dmg_colors: true,
            demo: false,
            pop: false,
            audio: false,
            mode: :ruby,
            sim: nil,
            hdl_dir: nil,
            top: nil,
            use_staged_verilog: false,
            renderer: :color,
            headless: false
          }

          parser = OptionParser.new do |opts|
            opts.banner = "Usage: #{program_name} [options] [rom.gb]"
            opts.separator ''
            opts.separator 'Game Boy HDL Terminal Emulator - Cycle-accurate simulation'
            opts.separator ''
            opts.separator 'Subcommands:'
            opts.separator '    import                         Import the Game Boy reference design into raised RHDL'
            opts.separator ''

            opts.on('-m', '--mode TYPE', %i[ruby ir verilog],
                    'Simulation mode: ruby (default), ir, verilog (Verilator RTL)') do |v|
              options[:mode] = v
            end

            opts.on('--sim TYPE', %i[ruby interpret jit compile],
                    'Simulator backend: ruby (default), interpret, jit, compile') do |v|
              options[:sim] = v
            end

            opts.on('--hdl-dir DIR', 'Game Boy HDL directory override (default: examples/gameboy/hdl)') do |v|
              options[:hdl_dir] = File.expand_path(v)
            end

            opts.on('--top NAME', 'Imported top component/module name override for imported HDL trees') do |v|
              options[:top] = v
            end

            opts.on('--use-staged-verilog', 'Use staged imported Verilog artifact when available') do
              options[:use_staged_verilog] = true
            end

            opts.on('--color', 'Use color renderer (default)') do
              options[:renderer] = :color
            end

            opts.on('--braille', 'Use braille renderer') do
              options[:renderer] = :braille
            end

            opts.on('-s', '--speed CYCLES', Integer, 'Cycles per frame (default: 100)') do |v|
              options[:speed] = v
            end

            opts.on('-d', '--debug', 'Show CPU state') do
              options[:debug] = true
            end

            opts.on('-g', '--green', 'DMG green palette (default)') do
              options[:dmg_colors] = true
            end

            opts.on('-A', '--audio', 'Enable audio output') do
              options[:audio] = true
            end

            opts.on('--demo', 'Run built-in demo') do
              options[:demo] = true
            end

            opts.on('--pop', 'Load Prince of Persia ROM') do
              options[:pop] = true
            end

            opts.on('--headless', 'Run without terminal UI (for testing)') do
              options[:headless] = true
            end

            opts.on('--cycles N', Integer, 'Number of cycles to run in headless mode') do |v|
              options[:cycles] = v
            end

            opts.on('--lcd-width WIDTH', Integer, 'LCD display width in chars (default: 80)') do |v|
              options[:lcd_width] = v
            end

            opts.on('-h', '--help', 'Show help') do
              out.puts opts
              options[:help] = true
            end
          end

          parser.parse!(args)
          return 0 if options[:help]

          if options[:hdl_dir] && !Dir.exist?(options[:hdl_dir])
            err.puts "Error: HDL directory not found: #{options[:hdl_dir]}"
            return 1
          end

          if options[:sim].nil?
            options[:sim] = case options[:mode]
                            when :ruby then :ruby
                            when :ir then :compile
                            when :verilog then :ruby
                            else :ruby
                            end
          end

          rom_file = args.shift
          if rom_file
            unless File.exist?(rom_file)
              err.puts "Error: ROM file not found: #{rom_file}"
              return 1
            end
            options[:rom_file] = rom_file
          elsif !options[:demo] && !options[:pop]
            err.puts parser
            err.puts
            err.puts 'Error: No ROM specified. Use --demo, --pop, or provide a ROM file.'
            return 1
          end

          result = run_task_class.new(options).run
          return 0 unless options[:headless] && result.is_a?(Hash)

          out.puts 'Final CPU state:'
          out.puts "  PC: $#{result[:pc].to_s(16).upcase.rjust(4, '0')}"
          out.puts "  A:  $#{result[:a].to_s(16).upcase.rjust(2, '0')}"
          out.puts "  Cycles: #{result[:cycles]}"
          0
        rescue OptionParser::ParseError => e
          err.puts "Error: #{e.message}"
          err.puts
          err.puts parser
          1
        rescue ArgumentError => e
          err.puts "Error: #{e.message}"
          1
        end


        def handle_import_failure(result, err:)
          diagnostics = Array(result.respond_to?(:diagnostics) ? result.diagnostics : nil)
          diagnostics = ['Game Boy import failed'] if diagnostics.empty?
          diagnostics.each { |message| err.puts(message) }
          1
        end

        def expand_path(path)
          return nil if path.nil? || path.to_s.strip.empty?

          File.expand_path(path, Dir.pwd)
        end

        def importer_constant(importer_class, name, fallback)
          return fallback unless importer_class.respond_to?(:const_defined?)

          importer_class.const_defined?(name, false) ? importer_class.const_get(name, false) : fallback
        end
      end
    end
  end
end
