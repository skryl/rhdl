# frozen_string_literal: true

require "fileutils"
require "json"

module RHDL
  module Import
    module Checks
      class TraceReportWriter
        class << self
          def write(**kwargs)
            new.write(**kwargs)
          end
        end

        def write(root_dir:, top:, summary:, mismatches:, profile: "ao486_trace")
          report_root = File.expand_path(root_dir)
          FileUtils.mkdir_p(report_root)

          report_path = File.join(report_root, "#{normalized_top_name(top)}_trace.json")
          report = {
            top: top.to_s,
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
            events_compared: value_for(hash, :events_compared) || 0,
            pass_count: value_for(hash, :pass_count) || 0,
            fail_count: value_for(hash, :fail_count) || 0,
            first_mismatch: value_for(hash, :first_mismatch)
          }
        end

        def normalize_mismatches(mismatches)
          Array(mismatches).map do |entry|
            hash = entry.is_a?(Hash) ? entry : {}
            {
              index: value_for(hash, :index) || 0,
              expected: value_for(hash, :expected),
              actual: value_for(hash, :actual)
            }
          end.sort_by { |entry| entry[:index] }
        end

        def normalized_top_name(top)
          candidate = top.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
          candidate.empty? ? "unnamed_top" : candidate
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
