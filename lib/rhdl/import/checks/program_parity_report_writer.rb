# frozen_string_literal: true

require "fileutils"
require "json"

module RHDL
  module Import
    module Checks
      class ProgramParityReportWriter
        class << self
          def write(**kwargs)
            new.write(**kwargs)
          end
        end

        def write(root_dir:, top:, summary:, mismatches:, traces:, profile: "ao486_program_parity")
          report_root = File.expand_path(root_dir)
          FileUtils.mkdir_p(report_root)

          report_path = File.join(report_root, "#{normalized_top_name(top)}_program_parity.json")
          report = {
            top: top.to_s,
            profile: profile.to_s,
            summary: normalize_summary(summary),
            mismatches: normalize_mismatches(mismatches),
            traces: normalize_traces(traces)
          }

          File.write(report_path, JSON.pretty_generate(report))
          report_path
        end

        private

        def normalize_summary(summary)
          hash = summary.is_a?(Hash) ? summary : {}
          {
            cycles_requested: value_for(hash, :cycles_requested) || 0,
            pc_events_compared: value_for(hash, :pc_events_compared) || 0,
            instruction_events_compared: value_for(hash, :instruction_events_compared) || 0,
            write_events_compared: value_for(hash, :write_events_compared) || 0,
            memory_words_compared: value_for(hash, :memory_words_compared) || 0,
            pass_count: value_for(hash, :pass_count) || 0,
            fail_count: value_for(hash, :fail_count) || 0,
            first_mismatch: value_for(hash, :first_mismatch)
          }
        end

        def normalize_mismatches(mismatches)
          Array(mismatches).map do |entry|
            hash = entry.is_a?(Hash) ? entry : {}
            {
              kind: value_for(hash, :kind).to_s,
              index: value_for(hash, :index) || 0,
              address: value_for(hash, :address),
              reference: value_for(hash, :reference),
              generated_verilog: value_for(hash, :generated_verilog),
              generated_ir: value_for(hash, :generated_ir)
            }
          end.sort_by { |entry| [entry[:kind], entry[:index].to_i, entry[:address].to_s] }
        end

        def normalize_traces(traces)
          hash = traces.is_a?(Hash) ? traces : {}
          %i[reference generated_verilog generated_ir].each_with_object({}) do |name, memo|
            source = value_for(hash, name)
            source_hash = source.is_a?(Hash) ? source : {}
            memo[name] = {
              pc_sequence: Array(value_for(source_hash, :pc_sequence)),
              instruction_sequence: Array(value_for(source_hash, :instruction_sequence)),
              memory_writes: Array(value_for(source_hash, :memory_writes)),
              memory_contents: value_for(source_hash, :memory_contents).is_a?(Hash) ? value_for(source_hash, :memory_contents) : {}
            }
          end
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
