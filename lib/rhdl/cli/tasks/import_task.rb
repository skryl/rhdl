# frozen_string_literal: true

require_relative '../task'
require 'fileutils'

module RHDL
  module CLI
    module Tasks
      # Import task for CIRCT-based ingestion flows.
      # Verilog parsing/emission is delegated to external LLVM/CIRCT tooling.
      class ImportTask < Task
        def run
          require 'rhdl'

          mode = options[:mode]&.to_sym
          case mode
          when :verilog
            import_verilog
          when :circt
            import_circt_mlir
          else
            raise ArgumentError, "Unknown import mode: #{mode.inspect}. Expected :verilog or :circt"
          end
        end

        private

        def import_verilog
          input = fetch_input_path
          out_dir = fetch_out_dir
          ensure_dir(out_dir)

          base = File.basename(input, File.extname(input))
          mlir_out = options[:mlir_out] || File.join(out_dir, "#{base}.mlir")
          tool = options[:tool] || RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL

          result = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
            verilog_path: input,
            out_path: mlir_out,
            tool: tool,
            extra_args: Array(options[:tool_args])
          )

          unless result[:success]
            raise RuntimeError,
                  "Verilog->CIRCT conversion failed with '#{tool}'.\nCommand: #{result[:command]}\n#{result[:stderr]}"
          end

          puts "Wrote CIRCT MLIR: #{mlir_out}"
          puts "Command: #{result[:command]}"

          return unless raise_to_dsl?

          run_raise_flow(mlir_out: mlir_out, out_dir: out_dir)
        end

        def import_circt_mlir
          input = fetch_input_path
          out_dir = fetch_out_dir
          ensure_dir(out_dir)

          unless raise_to_dsl?
            puts "CIRCT MLIR ready: #{input}"
            return
          end

          run_raise_flow(mlir_out: input, out_dir: out_dir)
        end

        def run_raise_flow(mlir_out:, out_dir:)
          mlir = File.read(mlir_out)
          result = RHDL::Codegen::CIRCT::Raise.to_dsl(
            mlir,
            out_dir: out_dir,
            top: options[:top]
          )

          result.diagnostics.each do |diag|
            level = diag.severity.to_s.upcase
            puts "[#{level}] #{diag.message}"
          end

          puts "Raised #{result.files_written.length} DSL file(s):"
          result.files_written.each { |path| puts "  - #{path}" }

          unless result.success?
            raise RuntimeError, 'CIRCT->RHDL raise completed with errors (partial output written)'
          end
        end

        def fetch_input_path
          input = options[:input]
          raise ArgumentError, 'Input file is required (--input)' if input.nil? || input.strip.empty?
          raise ArgumentError, "Input file not found: #{input}" unless File.exist?(input)

          input
        end

        def fetch_out_dir
          out_dir = options[:out]
          raise ArgumentError, 'Output directory is required (--out)' if out_dir.nil? || out_dir.strip.empty?

          out_dir
        end

        def raise_to_dsl?
          options.fetch(:raise_to_dsl, true)
        end
      end
    end
  end
end
