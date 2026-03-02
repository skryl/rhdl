# frozen_string_literal: true

require "fileutils"
require "json"

module RHDL
  module Import
    module Checks
      class ComponentParityReportWriter
        class << self
          def write(**kwargs)
            new.write(**kwargs)
          end
        end

        def write(root_dir:, component:, summary:, mismatches:, profile: "ao486_component_parity")
          report_root = File.expand_path(root_dir)
          FileUtils.mkdir_p(report_root)

          report_path = File.join(report_root, "#{normalized_component_name(component)}_component_parity.json")
          report = {
            component: component.to_s,
            profile: profile.to_s,
            summary: normalize_summary(summary),
            mismatches: normalize_mismatches(mismatches)
          }

          File.write(report_path, JSON.pretty_generate(report))
          report_path
        end

        private

        def normalize_summary(summary)
          hash = summary.is_a?(Hash) ? summary : {}

          {
            cycles_compared: value_for(hash, :cycles_compared) || 0,
            signals_compared: value_for(hash, :signals_compared) || 0,
            pass_count: value_for(hash, :pass_count) || 0,
            fail_count: value_for(hash, :fail_count) || 0
          }
        end

        def normalize_mismatches(mismatches)
          Array(mismatches).map do |entry|
            hash = entry.is_a?(Hash) ? entry : {}
            {
              cycle: value_for(hash, :cycle) || 0,
              signal: value_for(hash, :signal).to_s,
              original: value_for(hash, :original),
              generated_verilog: value_for(hash, :generated_verilog),
              generated_ir: value_for(hash, :generated_ir)
            }
          end.sort_by { |entry| [entry[:cycle], entry[:signal]] }
        end

        def normalized_component_name(component)
          candidate = component.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
          candidate.empty? ? "unnamed_component" : candidate
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
