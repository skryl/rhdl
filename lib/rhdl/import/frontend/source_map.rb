# frozen_string_literal: true

module RHDL
  module Import
    module Frontend
      class SourceMap
        attr_reader :sources

        class << self
          def build(raw_sources)
            new(raw_sources).build
          end
        end

        def initialize(raw_sources)
          @raw_sources = Array(raw_sources)
          @sources = []
          @by_original_id = {}
          @by_path = {}
        end

        def build
          normalized = @raw_sources.map { |entry| normalize_entry(entry) }
          normalized.sort_by { |entry| entry[:path] }.each_with_index do |entry, index|
            mapped = {
              id: index + 1,
              original_id: entry[:original_id],
              path: entry[:path]
            }
            @sources << mapped
            @by_original_id[mapped[:original_id]] ||= mapped if mapped[:original_id]
            @by_path[mapped[:path]] ||= mapped
          end
          self
        end

        def lookup_by_original_id(value)
          return nil if value.nil?

          @by_original_id[normalize_original_id(value)]
        end

        def lookup_by_path(path)
          @by_path[normalize_path(path)]
        end

        def to_h
          { sources: @sources }
        end

        private

        def normalize_entry(entry)
          hash = entry.is_a?(Hash) ? entry : {}
          {
            original_id: normalize_original_id(hash[:id] || hash["id"]),
            path: normalize_path(hash[:path] || hash["path"])
          }
        end

        def normalize_path(path)
          path.to_s.tr("\\", "/").sub(%r{\A\./}, "")
        end

        def normalize_original_id(value)
          return nil if value.nil?

          text = value.to_s.strip
          return nil if text.empty?
          return Integer(text) if text.match?(/\A\d+\z/)

          text
        end
      end
    end
  end
end
