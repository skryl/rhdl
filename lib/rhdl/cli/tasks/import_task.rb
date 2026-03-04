# frozen_string_literal: true

require_relative '../task'
require 'fileutils'
require 'json'

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
          strict = options.fetch(:strict, true)
          extern_modules = Array(options[:extern_modules]).map(&:to_s)

          import_result = RHDL::Codegen.import_circt_mlir(
            mlir,
            strict: strict,
            top: options[:top],
            extern_modules: extern_modules
          )
          emit_diagnostics(import_result.diagnostics)

          raise_result = RHDL::Codegen.raise_circt(
            import_result.modules,
            out_dir: out_dir,
            top: options[:top],
            strict: strict,
            format: true
          )
          emit_diagnostics(raise_result.diagnostics)

          puts "Raised #{raise_result.files_written.length} DSL file(s):"
          raise_result.files_written.each { |path| puts "  - #{path}" }

          report_path = write_report(
            out_dir: out_dir,
            strict: strict,
            extern_modules: extern_modules,
            import_result: import_result,
            raise_result: raise_result
          )
          puts "Wrote import report: #{report_path}"

          unless import_result.success? && raise_result.success?
            raise RuntimeError, 'CIRCT import/raise completed with errors (partial output written)'
          end
        end

        def emit_diagnostics(diags)
          Array(diags).each do |diag|
            level = diag.severity.to_s.upcase
            op = diag.respond_to?(:op) && diag.op ? " #{diag.op}:" : ''
            puts "[#{level}]#{op} #{diag.message}"
          end
        end

        def write_report(out_dir:, strict:, extern_modules:, import_result:, raise_result:)
          path = options[:report] || File.join(out_dir, 'import_report.json')
          report = {
            success: import_result.success? && raise_result.success?,
            strict: strict,
            top: options[:top],
            extern_modules: extern_modules,
            module_count: import_result.modules.length,
            op_census: import_result.op_census,
            modules: import_result.modules.map do |mod|
              mod_name = mod.name.to_s
              module_diags = Array(import_result.module_diagnostics.fetch(mod_name, []))
              span = import_result.module_spans[mod_name] || {}
              {
                name: mod_name,
                start_line: span[:start_line],
                end_line: span[:end_line],
                import_errors: module_diags.count { |diag| diag.severity.to_s == 'error' },
                import_warnings: module_diags.count { |diag| diag.severity.to_s == 'warning' },
                import_diagnostics: module_diags.map { |diag| diagnostic_to_hash(diag) }
              }
            end,
            import_diagnostics: Array(import_result.diagnostics).map { |diag| diagnostic_to_hash(diag) },
            raise_diagnostics: Array(raise_result.diagnostics).map { |diag| diagnostic_to_hash(diag) }
          }

          File.write(path, JSON.pretty_generate(report))
          path
        end

        def diagnostic_to_hash(diag)
          {
            severity: diag.respond_to?(:severity) ? diag.severity.to_s : nil,
            op: diag.respond_to?(:op) ? diag.op : nil,
            message: diag.respond_to?(:message) ? diag.message : diag.to_s,
            line: diag.respond_to?(:line) ? diag.line : nil,
            column: diag.respond_to?(:column) ? diag.column : nil
          }
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
