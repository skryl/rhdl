# frozen_string_literal: true

module RHDL
  module Import
    class Mapper
      module Helpers
        private

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

        def integer_or_default(value, default)
          Integer(value)
        rescue ArgumentError, TypeError
          default
        end

        def normalize_span(span)
          hash = normalize_hash(span)
          return nil if hash.empty?

          line = integer_or_default(value_for(hash, :line), 1)
          column = integer_or_default(value_for(hash, :column), 1)
          end_line = integer_or_default(value_for(hash, :end_line), line)
          end_column = integer_or_default(value_for(hash, :end_column), column)

          IR::Span.new(
            source_id: value_for(hash, :source_id),
            source_path: value_for(hash, :source_path) || value_for(hash, :path),
            line: line,
            column: column,
            end_line: end_line,
            end_column: end_column
          )
        end

        def span_to_hash(span)
          return nil unless span

          span.to_h
        end

        def unsupported_construct!(diagnostics:, family:, construct:, node:, module_name:)
          normalized_construct = construct.to_s.empty? ? "unknown" : construct.to_s
          span = normalize_span(value_for(normalize_hash(node), :span))

          diagnostics << {
            severity: "error",
            code: "unsupported_construct",
            message: "Unsupported #{family} construct: #{normalized_construct}",
            tags: ["mapper", "unsupported_construct", family.to_s],
            module: module_name,
            construct: normalized_construct,
            span: span_to_hash(span)
          }

          nil
        end
      end
    end
  end
end
