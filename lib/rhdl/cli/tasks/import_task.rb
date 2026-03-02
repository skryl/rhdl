# frozen_string_literal: true

require_relative '../task'
require_relative '../../import'

module RHDL
  module CLI
    module Tasks
      class ImportTask < Task
        DEFAULT_OUT_DIR = "rhdl_import"

        def run
          result = import_api.project(**project_options)
          print_summary(result)
          result.success?
        rescue StandardError => e
          error_output.puts("Import failed: #{e.message}")
          false
        end

        private

        def import_api
          option_value(:import_api) || RHDL::Import
        end

        def project_options
          forwarded = options.dup
          forwarded.delete(:import_api)
          forwarded.delete(:stdout)
          forwarded.delete(:stderr)

          forwarded[:out] = resolve_out_dir
          forwarded
        end

        def resolve_out_dir
          out = option_value(:out).to_s
          return out unless out.empty?

          remaining_args = Array(option_value(:remaining_args)).map(&:to_s).reject(&:empty?)
          return remaining_args.first unless remaining_args.empty?

          File.join(Dir.pwd, DEFAULT_OUT_DIR)
        end

        def print_summary(result)
          summary = normalize_hash(value_for(result.report, :summary))
          converted_modules = integer_or_default(value_for(summary, :converted_modules), Array(result.converted_modules).length)
          failed_modules = integer_or_default(value_for(summary, :failed_modules), Array(result.failed_modules).length)
          checks_failed = integer_or_default(value_for(summary, :checks_failed), 0)
          status = result.success? ? "success" : "failure"

          output.puts("Import #{status}: converted=#{converted_modules}, failed=#{failed_modules}, checks_failed=#{checks_failed}")
          output.puts("Output: #{result.out_dir}")
          output.puts("Report: #{result.report_path}")
        end

        def output
          option_value(:stdout) || $stdout
        end

        def error_output
          option_value(:stderr) || $stderr
        end

        def integer_or_default(value, default)
          Integer(value)
        rescue ArgumentError, TypeError
          default
        end

        def normalize_hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def value_for(hash, key)
          return nil unless hash.is_a?(Hash)

          return hash[key] if hash.key?(key)

          string_key = key.to_s
          return hash[string_key] if hash.key?(string_key)

          symbol_key = key.to_sym
          return hash[symbol_key] if hash.key?(symbol_key)

          nil
        end

        def option_value(key)
          return options[key] if options.key?(key)

          string_key = key.to_s
          return options[string_key] if options.key?(string_key)

          symbol_key = key.to_sym
          return options[symbol_key] if options.key?(symbol_key)

          nil
        end
      end
    end
  end
end
