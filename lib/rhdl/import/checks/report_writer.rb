# frozen_string_literal: true

require "fileutils"
require "json"

module RHDL
  module Import
    module Checks
      class ReportWriter
        class << self
          def write(**kwargs)
            new.write(**kwargs)
          end
        end

        def write(root_dir:, top:, summary:, mismatches:)
          report_root = File.expand_path(root_dir)
          FileUtils.mkdir_p(report_root)

          report_path = File.join(report_root, "#{normalized_top_name(top)}_differential.json")
          report = {
            top: top.to_s,
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
              cycle: normalize_cycle(value_for(hash, :cycle)),
              signal: value_for(hash, :signal).to_s,
              expected: value_for(hash, :expected),
              actual: value_for(hash, :actual)
            }
          end.sort_by do |entry|
            [cycle_sort_key(entry[:cycle]), entry[:signal]]
          end
        end

        def cycle_sort_key(cycle)
          if cycle.is_a?(Numeric)
            [0, cycle]
          else
            [1, cycle.to_s]
          end
        end

        def normalize_cycle(cycle)
          return cycle if cycle.is_a?(Numeric)

          text = cycle.to_s.strip
          return text.to_i if text.match?(/\A\d+\z/)

          text
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
