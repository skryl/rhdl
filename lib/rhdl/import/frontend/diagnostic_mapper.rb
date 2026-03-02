# frozen_string_literal: true

module RHDL
  module Import
    module Frontend
      class DiagnosticMapper
        SEVERITY_ORDER = {
          "error" => 0,
          "warning" => 1,
          "note" => 2,
          "info" => 3
        }.freeze

        class << self
          def map(diagnostics:, source_map:)
            new(diagnostics: diagnostics, source_map: source_map).map
          end
        end

        def initialize(diagnostics:, source_map:)
          @diagnostics = Array(diagnostics)
          @source_map = source_map
        end

        def map
          @diagnostics
            .map { |diagnostic| normalize_diagnostic(diagnostic) }
            .sort_by { |diagnostic| [severity_rank(diagnostic[:severity]), diagnostic[:code].to_s, diagnostic[:message].to_s] }
        end

        private

        def normalize_diagnostic(diagnostic)
          hash = diagnostic.is_a?(Hash) ? diagnostic : {}
          span_input = extract_span(hash)
          source = resolve_source(span_input)

          line = integer_or_default(span_input[:line], 1)
          column = integer_or_default(span_input[:column], 1)
          end_line = integer_or_default(span_input[:end_line], line)
          end_column = integer_or_default(span_input[:end_column], column)

          {
            severity: normalize_severity(value_for(hash, :severity)),
            code: value_for(hash, :code),
            message: value_for(hash, :message).to_s,
            span: {
              source_id: source && source[:id],
              source_path: source ? source[:path] : span_input[:path],
              line: line,
              column: column,
              end_line: end_line,
              end_column: end_column
            }
          }
        end

        def extract_span(diagnostic)
          span = value_for(diagnostic, :span)
          location = value_for(diagnostic, :location)

          source_id = value_for(span, :source_id)
          source_path = normalize_path(value_for(span, :source_path) || value_for(span, :file) || value_for(span, :path))

          line = value_for(span, :line)
          column = value_for(span, :column)
          end_line = value_for(span, :end_line)
          end_column = value_for(span, :end_column)

          source_id ||= value_for(location, :source_id)
          source_path ||= normalize_path(value_for(location, :file) || value_for(location, :path))

          start = value_for(location, :start)
          finish = value_for(location, :end)

          line ||= value_for(start, :line) || value_for(location, :line)
          column ||= value_for(start, :column) || value_for(location, :column)
          end_line ||= value_for(finish, :line)
          end_column ||= value_for(finish, :column)

          source_path ||= normalize_path(value_for(diagnostic, :file))
          line ||= value_for(diagnostic, :line)
          column ||= value_for(diagnostic, :column)

          {
            source_id: source_id,
            path: source_path,
            line: line,
            column: column,
            end_line: end_line,
            end_column: end_column
          }
        end

        def resolve_source(span_input)
          source = @source_map.lookup_by_original_id(span_input[:source_id])
          source ||= @source_map.lookup_by_path(span_input[:path])
          source
        end

        def normalize_severity(value)
          severity = value.to_s.strip.downcase
          severity.empty? ? "info" : severity
        end

        def severity_rank(severity)
          SEVERITY_ORDER.fetch(severity, SEVERITY_ORDER["info"] + 1)
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

        def normalize_path(path)
          return nil if path.nil?

          path.to_s.tr("\\", "/").sub(%r{\A\./}, "")
        end

        def integer_or_default(value, default)
          Integer(value)
        rescue ArgumentError, TypeError
          default
        end
      end
    end
  end
end
