# frozen_string_literal: true

require 'json'
require_relative '../examples/gameboy/import/unit/support'

module GameboyImportSemanticHelper
  include GameBoyImportUnitSupport
  extend self

  COMPONENT_MANIFEST_KEYS = %w[
    components
    component_provenance
    component_manifest
    per_component_manifest
  ].freeze

  COMPONENT_MANIFEST_PATH_KEYS = %w[
    component_manifest_path
    per_component_manifest_path
  ].freeze

  def load_component_manifest(report_path)
    report = JSON.parse(File.read(report_path))
    component_provenance_entries(report)
  rescue RuntimeError
    path = component_manifest_path_from_report(report, report_path)
    return unless path && File.file?(path)

    payload = JSON.parse(File.read(path))
    return payload if payload.is_a?(Array)
    return payload['components'] if payload.is_a?(Hash) && payload['components'].is_a?(Array)

    nil
  end

  def component_manifest_path_from_report(report, report_path)
    candidates = []
    COMPONENT_MANIFEST_PATH_KEYS.each do |key|
      candidates << report[key]
      candidates << report.fetch('artifacts', {})[key]
    end
    path = candidates.compact.first
    return unless path

    File.expand_path(path, File.dirname(report_path))
  end

  def missing_component_manifest_message(report_path)
    "GameBoy import report at #{report_path} is missing per-component provenance. Expected one of #{COMPONENT_MANIFEST_KEYS.inspect} or a path under #{COMPONENT_MANIFEST_PATH_KEYS.inspect}."
  end
end
