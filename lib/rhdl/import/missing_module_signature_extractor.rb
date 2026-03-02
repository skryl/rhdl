# frozen_string_literal: true

require "set"

module RHDL
  module Import
    class MissingModuleSignatureExtractor
      class << self
        def augment(signatures:, source_files:)
          new.augment(signatures: signatures, source_files: source_files)
        end
      end

      def augment(signatures:, source_files:)
        normalized = normalize_signatures(signatures)
        return normalized if normalized.empty?

        source_paths = Array(source_files).map(&:to_s).map(&:strip).reject(&:empty?).uniq.sort
        return normalized if source_paths.empty?

        by_name = normalized.each_with_object({}) { |entry, memo| memo[entry[:name]] = entry }

        source_paths.each do |path|
          next unless File.file?(path)

          source = read_source(path)
          next if source.empty?

          by_name.each_value do |signature|
            extract_instances(source: source, module_name: signature[:name]).each do |instance|
              signature[:ports].merge(instance[:ports])
              signature[:parameters].merge(instance[:parameters])
            end
          end
        end

        by_name.values.map do |entry|
          {
            name: entry[:name],
            ports: entry[:ports].to_a.sort,
            parameters: entry[:parameters].to_a.sort,
            referenced_by: entry[:referenced_by].to_a.sort
          }
        end.sort_by { |entry| entry[:name] }
      end

      private

      def normalize_signatures(signatures)
        Array(signatures).filter_map do |entry|
          hash = normalize_hash(entry)
          name = value_for(hash, :name).to_s.strip
          next if name.empty?

          {
            name: name,
            ports: Set.new(normalize_names(value_for(hash, :ports))),
            parameters: Set.new(normalize_names(value_for(hash, :parameters))),
            referenced_by: Set.new(normalize_names(value_for(hash, :referenced_by)))
          }
        end.sort_by { |entry| entry[:name] }
      end

      def normalize_names(values)
        Array(values).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      end

      def read_source(path)
        strip_comments(File.read(path))
      rescue StandardError
        ""
      end

      def strip_comments(source)
        no_block = source.gsub(%r{/\*.*?\*/}m, " ")
        no_block.gsub(%r{//[^\n]*}, "")
      end

      def extract_instances(source:, module_name:)
        pattern = /\b#{Regexp.escape(module_name)}\b/
        offset = 0
        instances = []

        while (match = pattern.match(source, offset))
          cursor = skip_whitespace(source, match.end(0))
          parameter_block = nil

          if source[cursor] == "#"
            cursor = skip_whitespace(source, cursor + 1)
            parameter_block, cursor = extract_paren_block(source, cursor)
            offset = match.end(0) and next if parameter_block.nil?
            cursor = skip_whitespace(source, cursor)
          end

          _instance_name, cursor = extract_identifier(source, cursor)
          offset = match.end(0) and next if cursor.nil?
          cursor = skip_whitespace(source, cursor)

          port_block, cursor = extract_paren_block(source, cursor)
          offset = match.end(0) and next if port_block.nil?

          cursor = skip_whitespace(source, cursor)
          offset = match.end(0) and next unless source[cursor] == ";"

          instances << {
            parameters: extract_named_bindings(parameter_block),
            ports: extract_named_bindings(port_block)
          }
          offset = cursor + 1
        end

        instances
      end

      def extract_named_bindings(block)
        return [] unless block.is_a?(String)

        block.scan(/\.\s*([A-Za-z_][A-Za-z0-9_$]*)\s*\(/).flatten.uniq
      end

      def skip_whitespace(text, cursor)
        index = cursor
        while index < text.length && text[index].match?(/\s/)
          index += 1
        end
        index
      end

      def extract_identifier(text, cursor)
        match = /\A([A-Za-z_][A-Za-z0-9_$]*)/.match(text[cursor..] || "")
        return [nil, nil] if match.nil?

        [match[1], cursor + match[0].length]
      end

      def extract_paren_block(text, cursor)
        return [nil, cursor] unless text[cursor] == "("

        depth = 0
        index = cursor
        while index < text.length
          case text[index]
          when "("
            depth += 1
          when ")"
            depth -= 1
            if depth.zero?
              content = text[(cursor + 1)...index]
              return [content, index + 1]
            end
          end
          index += 1
        end

        [nil, cursor]
      end

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
    end
  end
end
