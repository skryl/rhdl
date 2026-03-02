# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module RHDL
  module Import
    module Report
      REPORT_RELATIVE_PATH = File.join("reports", "import_report.json").freeze

      class << self
        def build(
          out:,
          options:,
          status:,
          diagnostics: [],
          checks: [],
          converted_modules: [],
          failed_modules: [],
          blackboxes_generated: [],
          summary: nil,
          recovery: nil,
          hints: nil
        )
          converted_modules = Array(converted_modules)
          failed_modules = Array(failed_modules)
          checks = Array(checks)
          blackboxes_generated = Array(blackboxes_generated)
          normalized_hints = normalize_hints(hints, options: options)
          normalized_recovery = normalize_recovery(recovery, hints: normalized_hints)

          {
            schema_version: 1,
            generated_at: Time.now.utc.iso8601,
            status: status.to_s,
            project: {
              out_dir: out,
              options: options,
              tops: Array(options[:top])
            },
            summary: summary || default_summary(
              converted_modules: converted_modules,
              failed_modules: failed_modules,
              checks: checks,
              blackboxes_generated: blackboxes_generated
            ),
            modules: {
              converted: converted_modules,
              failed: failed_modules
            },
            blackboxes_generated: blackboxes_generated,
            recovery: normalized_recovery,
            hints: normalized_hints,
            diagnostics: Array(diagnostics),
            checks: checks
          }
        end

        def write(report, out:)
          report_path = File.join(out, REPORT_RELATIVE_PATH)
          FileUtils.mkdir_p(File.dirname(report_path))
          File.write(report_path, JSON.pretty_generate(report))
          report_path
        end

        private

        def default_summary(converted_modules:, failed_modules:, checks:, blackboxes_generated:)
          {
            total_modules: converted_modules.length + failed_modules.length,
            converted_modules: converted_modules.length,
            failed_modules: failed_modules.length,
            blackboxes_generated: blackboxes_generated.length,
            checks_run: checks.length,
            checks_failed: checks.count { |check| check_failed?(check) }
          }
        end

        def normalize_recovery(recovery, hints:)
          hash = recovery.is_a?(Hash) ? recovery : {}
          summary = value_for(hash, :summary)
          events = value_for(hash, :events)
          hint_applied_count = integer_or_default(value_for(hints, :applied_count), 0)

          {
            summary: {
              preserved_count: integer_or_default(value_for(summary, :preserved_count), 0),
              lowered_count: integer_or_default(value_for(summary, :lowered_count), 0),
              nonrecoverable_count: integer_or_default(value_for(summary, :nonrecoverable_count), 0),
              hint_applied_count: integer_or_default(value_for(summary, :hint_applied_count), hint_applied_count)
            },
            events: Array(events)
          }
        end

        def normalize_hints(hints, options:)
          hash = hints.is_a?(Hash) ? hints : {}
          backend = value_for(hash, :backend).to_s
          backend = value_for(options, :hint_backend).to_s if backend.empty?
          backend = "off" if backend.empty?
          diagnostics = Array(value_for(hash, :diagnostics))
          summary = normalize_hint_summary(value_for(hash, :summary), diagnostics: diagnostics)
          applied_count = integer_or_default(value_for(hash, :applied_count), summary[:applied_count])

          {
            backend: backend,
            available: truthy?(value_for(hash, :available)),
            applied_count: applied_count,
            summary: summary,
            diagnostics: diagnostics
          }
        end

        def normalize_hint_summary(summary, diagnostics:)
          hash = summary.is_a?(Hash) ? summary : {}
          extracted_count = integer_or_default(value_for(hash, :extracted_count), 0)
          applied_count = integer_or_default(value_for(hash, :applied_count), 0)
          discarded_default = [extracted_count - applied_count, 0].max
          discarded_count = integer_or_default(value_for(hash, :discarded_count), discarded_default)
          conflict_default = Array(diagnostics).count { |entry| value_for(entry, :code).to_s == "hint_conflict" }
          conflict_count = integer_or_default(value_for(hash, :conflict_count), conflict_default)

          {
            extracted_count: extracted_count,
            applied_count: applied_count,
            discarded_count: discarded_count,
            conflict_count: conflict_count
          }
        end

        def check_failed?(check)
          status = value_for(check, :status).to_s
          !%w[pass skipped success ok].include?(status)
        end

        def truthy?(value)
          case value
          when true then true
          when false, nil then false
          when Numeric then !value.zero?
          else
            %w[1 true yes on].include?(value.to_s.strip.downcase)
          end
        end

        def integer_or_default(value, default)
          Integer(value)
        rescue ArgumentError, TypeError
          default
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
      end
    end
  end
end
