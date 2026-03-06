# frozen_string_literal: true
require 'json'
require 'fileutils'

module RHDL
  module CLI
    module Tasks
      # Task for AO486 CIRCT import + bounded parity verification workflows.
      class AO486Task
        DEFAULT_IMPORT_SPEC = 'spec/examples/ao486/import/system_importer_spec.rb'
        DEFAULT_PARITY_SPEC = 'spec/examples/ao486/import/parity_spec.rb'
        DEFAULT_IMPORT_PATH_SPEC = 'spec/rhdl/import/import_paths_spec.rb'

        attr_reader :options

        def initialize(options = {})
          @options = options
        end

        def run
          action = (options[:action] || :import).to_sym

          case action
          when :import
            run_import
          when :parity
            run_specs([DEFAULT_PARITY_SPEC])
          when :verify
            run_specs([DEFAULT_IMPORT_SPEC, DEFAULT_PARITY_SPEC, DEFAULT_IMPORT_PATH_SPEC])
          else
            raise ArgumentError, "Unknown AO486 action: #{action.inspect}. Expected :import, :parity, or :verify"
          end
        end

        private

        def run_import
          output_dir = options[:output_dir]
          if output_dir.to_s.strip.empty?
            raise ArgumentError, 'AO486 import requires output_dir (--out DIR or rake ao486:import[output_dir,...])'
          end

          progress = options.fetch(:progress, nil) || lambda { |message| puts "AO486 import step: #{message}" }
          importer = importer_class.new(
            source_path: options[:source_path] || importer_class::DEFAULT_SOURCE_PATH,
            output_dir: output_dir,
            top: options[:top] || importer_class::DEFAULT_TOP,
            keep_workspace: options.fetch(:keep_workspace, false),
            workspace_dir: options[:workspace_dir],
            clean_output: options.fetch(:clean_output, true),
            import_strategy: options[:import_strategy] || importer_class::DEFAULT_IMPORT_STRATEGY,
            fallback_to_stubbed: options.fetch(:fallback_to_stubbed, true),
            maintain_directory_structure: options.fetch(:maintain_directory_structure, true),
            format_output: options.fetch(:format_output, false),
            strict: options.fetch(:strict, true),
            progress: progress
          )

          result = importer.run
          serialized_raise = serialize_raise_diagnostics(
            result.respond_to?(:raise_diagnostics) ? Array(result.raise_diagnostics) : []
          )
          missing_ops_summary = summarize_missing_ops(serialized_raise)
          strict_gate_passed = missing_ops_summary.empty?
          overall_success = result.success? && strict_gate_passed

          puts "AO486 import success=#{result.success?} files=#{Array(result.files_written).length}"
          puts "AO486 import output=#{result.output_dir}" if result.respond_to?(:output_dir)
          puts "AO486 import workspace=#{result.workspace}" if result.respond_to?(:workspace) && result.workspace
          if result.respond_to?(:strategy_used) && result.strategy_used
            puts "AO486 import strategy=#{result.strategy_used} fallback=#{result.respond_to?(:fallback_used) ? result.fallback_used : false}"
          end
          if result.respond_to?(:attempted_strategies) && result.attempted_strategies
            puts "AO486 import attempts=#{Array(result.attempted_strategies).join(',')}"
          end
          if result.respond_to?(:stub_modules) && result.stub_modules
            puts "AO486 import stubs=#{Array(result.stub_modules).length}"
          end
          if strict_gate_passed
            puts 'AO486 strict_gate=pass'
          else
            puts "AO486 strict_gate=fail blocking=#{missing_ops_summary.keys.sort.join(',')}"
          end
          report_path = write_report(
            result,
            serialized_raise: serialized_raise,
            missing_ops_summary: missing_ops_summary,
            strict_gate_passed: strict_gate_passed
          )
          puts "AO486 import report=#{report_path}" if report_path
          diagnostics = Array(result.diagnostics)
          if result.success?
            diagnostics.first(10).each { |line| puts line }
            omitted = diagnostics.length - 10
            puts "AO486 import diagnostics omitted=#{omitted}" if omitted.positive?
          else
            diagnostics.each { |line| puts line }
          end

          return if overall_success

          raise RuntimeError, 'AO486 import failed'
        end

        def run_specs(paths)
          cmd = rspec_command(paths)
          ok = spec_runner.call(cmd)
          return if ok

          raise RuntimeError, "AO486 spec run failed: #{cmd.join(' ')}"
        end

        def rspec_command(paths)
          bin_rspec = File.expand_path('../../../../bin/rspec', __dir__)
          if File.executable?(bin_rspec)
            [bin_rspec, *paths, '--format', 'progress']
          else
            ['bundle', 'exec', 'rspec', *paths, '--format', 'progress']
          end
        end

        def spec_runner
          options[:spec_runner] || lambda { |cmd| system(*cmd) }
        end

        def importer_class
        return options[:importer_class] if options[:importer_class]

        require_relative '../../../../examples/ao486/utilities/import/system_importer'
        RHDL::Examples::AO486::Import::SystemImporter
        end

        def write_report(result, serialized_raise: nil, missing_ops_summary: nil, strict_gate_passed: nil)
          report_path = options[:report]
          return nil if report_path.to_s.strip.empty?

          serialized_raise ||= serialize_raise_diagnostics(
            result.respond_to?(:raise_diagnostics) ? Array(result.raise_diagnostics) : []
          )
          missing_ops_summary ||= summarize_missing_ops(serialized_raise)
          strict_gate_passed = missing_ops_summary.empty? if strict_gate_passed.nil?

          payload = {
            success: (result.respond_to?(:success?) ? result.success? : false) && strict_gate_passed,
            output_dir: result.respond_to?(:output_dir) ? result.output_dir : nil,
            workspace: result.respond_to?(:workspace) ? result.workspace : nil,
            strategy_requested: result.respond_to?(:strategy_requested) ? result.strategy_requested : nil,
            strategy_used: result.respond_to?(:strategy_used) ? result.strategy_used : nil,
            fallback_used: result.respond_to?(:fallback_used) ? result.fallback_used : nil,
            attempted_strategies: result.respond_to?(:attempted_strategies) ? Array(result.attempted_strategies) : [],
            stub_modules: result.respond_to?(:stub_modules) ? Array(result.stub_modules) : [],
            files_written: result.respond_to?(:files_written) ? Array(result.files_written) : [],
            artifact_paths: {
              moore_mlir_path: result.respond_to?(:moore_mlir_path) ? result.moore_mlir_path : nil,
              core_mlir_path: result.respond_to?(:core_mlir_path) ? result.core_mlir_path : nil,
              normalized_core_mlir_path: result.respond_to?(:normalized_core_mlir_path) ? result.normalized_core_mlir_path : nil
            },
            diagnostics: result.respond_to?(:diagnostics) ? Array(result.diagnostics) : [],
            raise_diagnostics: serialized_raise,
            command_log: result.respond_to?(:command_log) ? Array(result.command_log) : []
          }
          payload[:missing_ops_summary] = missing_ops_summary
          payload[:strict_gate] = {
            passed: strict_gate_passed,
            blocking_categories: missing_ops_summary.keys.sort
          }

          FileUtils.mkdir_p(File.dirname(report_path))
          File.write(report_path, JSON.pretty_generate(payload))
          report_path
        end

        def serialize_raise_diagnostics(diags)
          diags.map do |diag|
            {
              severity: diag.respond_to?(:severity) ? diag.severity.to_s : nil,
              op: diag.respond_to?(:op) ? diag.op : nil,
              message: diag.respond_to?(:message) ? diag.message : diag.to_s,
              line: diag.respond_to?(:line) ? diag.line : nil,
              column: diag.respond_to?(:column) ? diag.column : nil
            }
          end
        end

        def summarize_missing_ops(diags)
          summary = Hash.new(0)
          Array(diags).each do |diag|
            key = missing_op_key(diag)
            summary[key] += 1 if key
          end
          summary.keys.sort.each_with_object({}) { |key, out| out[key] = summary[key] }
        end

        def missing_op_key(diag)
          op = diag[:op].to_s
          message = diag[:message].to_s

          case op
          when 'parser'
            skipped = message[/Unsupported MLIR line, skipped:\s*(.+)\z/, 1]
            return nil unless skipped

            parser_op = if skipped.start_with?('%')
                          skipped[/=\s*([A-Za-z_][A-Za-z0-9_.]*)\b/, 1]
                        else
                          skipped[/\A([A-Za-z_][A-Za-z0-9_.]*)\b/, 1]
                        end
            return "parser:#{parser_op || 'unknown'}"
          when 'comb.icmp'
            return 'comb.icmp:predicate_fallback' if message.include?('Unsupported comb.icmp predicate')
          when 'comb.add'
            return 'comb.add:variadic' if message.include?('Unsupported variadic comb.add')
          when 'raise.structure'
            return 'raise.structure:unsupported_instance_input_connection' if message.include?('Unsupported instance input connection')
          when 'raise.behavior'
            return 'raise.behavior:placeholder' if message.include?('placeholder')
          end

          nil
        end
      end
    end
  end
end
