# frozen_string_literal: true

require "set"

module RHDL
  module Import
    class TopDetector
      class << self
        def detect(modules:, explicit_tops: nil)
          new(modules: modules).detect(explicit_tops: explicit_tops)
        end
      end

      def initialize(modules:)
        @modules = normalize_modules(modules)
        @module_names = @modules.map { |entry| entry[:name] }
        @module_name_set = @module_names.to_set
      end

      def detect(explicit_tops: nil)
        requested_tops = unique_non_empty(Array(explicit_tops).map(&:to_s))
        return validate_explicit_tops(requested_tops) if requested_tops.any?

        referenced_modules = Set.new
        @modules.each do |entry|
          entry[:dependencies].each do |dependency|
            referenced_modules << dependency if @module_name_set.include?(dependency)
          end
        end

        (@module_names - referenced_modules.to_a).sort
      end

      private

      def validate_explicit_tops(requested_tops)
        unknown = requested_tops.reject { |name| @module_name_set.include?(name) }
        raise ArgumentError, "unknown top modules: #{unknown.join(', ')}" unless unknown.empty?

        requested_tops
      end

      def normalize_modules(modules)
        Array(modules).map { |entry| normalize_module(entry) }.reject { |entry| entry[:name].empty? }
      end

      def normalize_module(entry)
        hash = entry.is_a?(Hash) ? entry : {}
        {
          name: value_for(hash, :name).to_s,
          dependencies: extract_dependencies(hash)
        }
      end

      def extract_dependencies(entry)
        explicit_dependencies = value_for(entry, :dependencies)
        if !explicit_dependencies.nil?
          return unique_non_empty(Array(explicit_dependencies).map(&:to_s))
        end

        instances = Array(value_for(entry, :instances))
        dependencies = instances.map do |instance|
          instance_hash = instance.is_a?(Hash) ? instance : {}
          value_for(instance_hash, :module_name) || value_for(instance_hash, :module)
        end

        unique_non_empty(dependencies.map(&:to_s))
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

      def unique_non_empty(values)
        values.each_with_object([]) do |value, memo|
          next if value.nil? || value.empty? || memo.include?(value)

          memo << value
        end
      end
    end
  end
end
