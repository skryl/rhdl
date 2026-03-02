# frozen_string_literal: true

require "json"

module ImportHelpers
  IMPORT_FIXTURE_ROOT = File.expand_path("../fixtures/import", __dir__)

  REPORT_REQUIRED_KEYS = %w[
    schema_version
    generated_at
    status
    project
    summary
    modules
    blackboxes_generated
    recovery
    hints
    diagnostics
    checks
  ].freeze

  REPORT_PROJECT_KEYS = %w[
    out_dir
    options
    tops
  ].freeze

  REPORT_SUMMARY_KEYS = %w[
    total_modules
    converted_modules
    failed_modules
    blackboxes_generated
    checks_run
    checks_failed
  ].freeze

  REPORT_MODULE_KEYS = %w[
    converted
    failed
  ].freeze

  REPORT_RECOVERY_KEYS = %w[
    summary
    events
  ].freeze

  REPORT_RECOVERY_SUMMARY_KEYS = %w[
    preserved_count
    lowered_count
    nonrecoverable_count
    hint_applied_count
  ].freeze

  REPORT_HINTS_KEYS = %w[
    backend
    available
    applied_count
    summary
    diagnostics
  ].freeze

  REPORT_HINTS_SUMMARY_KEYS = %w[
    extracted_count
    applied_count
    discarded_count
    conflict_count
  ].freeze

  def import_fixture_path(*parts)
    File.join(IMPORT_FIXTURE_ROOT, *parts)
  end

  def load_import_fixture_json(*parts)
    JSON.parse(File.read(import_fixture_path(*parts)))
  end

  def normalize_import_exit_code(value)
    return value if value.is_a?(Integer)
    return value.exitstatus if value.respond_to?(:exitstatus)

    raise ArgumentError,
          "expected Integer or object responding to #exitstatus, got #{value.class}"
  end

  def non_zero_import_exit?(value)
    !normalize_import_exit_code(value).zero?
  end

  def assert_non_zero_import_exit!(value)
    code = normalize_import_exit_code(value)
    return code unless code.zero?

    raise ArgumentError, "expected non-zero import exit code, got 0"
  end

  def assert_import_report_skeleton!(report, status: nil)
    normalized = deep_stringify(report)

    ensure_hash_keys!(normalized, REPORT_REQUIRED_KEYS, "report")
    ensure_hash_keys!(normalized.fetch("project"), REPORT_PROJECT_KEYS, "project")
    ensure_hash_keys!(normalized.fetch("summary"), REPORT_SUMMARY_KEYS, "summary")
    ensure_hash_keys!(normalized.fetch("modules"), REPORT_MODULE_KEYS, "modules")
    ensure_hash_keys!(normalized.fetch("recovery"), REPORT_RECOVERY_KEYS, "recovery")
    ensure_hash_keys!(normalized.dig("recovery", "summary"), REPORT_RECOVERY_SUMMARY_KEYS, "recovery.summary")
    ensure_hash_keys!(normalized.fetch("hints"), REPORT_HINTS_KEYS, "hints")
    ensure_hash_keys!(normalized.dig("hints", "summary"), REPORT_HINTS_SUMMARY_KEYS, "hints.summary")

    raise ArgumentError, "project.options must be a Hash" unless normalized.dig("project", "options").is_a?(Hash)
    raise ArgumentError, "project.tops must be an Array" unless normalized.dig("project", "tops").is_a?(Array)
    raise ArgumentError, "modules.converted must be an Array" unless normalized.dig("modules", "converted").is_a?(Array)
    raise ArgumentError, "modules.failed must be an Array" unless normalized.dig("modules", "failed").is_a?(Array)
    raise ArgumentError, "blackboxes_generated must be an Array" unless normalized["blackboxes_generated"].is_a?(Array)
    raise ArgumentError, "recovery.events must be an Array" unless normalized.dig("recovery", "events").is_a?(Array)
    raise ArgumentError, "hints.diagnostics must be an Array" unless normalized.dig("hints", "diagnostics").is_a?(Array)
    raise ArgumentError, "diagnostics must be an Array" unless normalized["diagnostics"].is_a?(Array)
    raise ArgumentError, "checks must be an Array" unless normalized["checks"].is_a?(Array)

    if status
      expected_status = status.to_s
      actual_status = normalized.fetch("status")
      raise ArgumentError, "expected status #{expected_status.inspect}, got #{actual_status.inspect}" unless actual_status == expected_status
    end

    normalized
  end

  private

  def deep_stringify(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, inner), memo|
        memo[key.to_s] = deep_stringify(inner)
      end
    when Array
      value.map { |inner| deep_stringify(inner) }
    else
      value
    end
  end

  def ensure_hash_keys!(hash, required_keys, label)
    raise ArgumentError, "#{label} must be a Hash" unless hash.is_a?(Hash)

    missing = required_keys - hash.keys
    return if missing.empty?

    raise ArgumentError, "missing #{label} keys: #{missing.join(', ')}"
  end
end

RSpec.configure do |config|
  config.include ImportHelpers
end
