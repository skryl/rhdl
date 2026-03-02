# frozen_string_literal: true

require "set"

module RHDL
  module Import
    class DependencyGraph
      def initialize(modules:)
        @modules = {}
        @dependencies = {}

        normalize_modules(modules).each do |entry|
          @modules[entry[:name]] = entry
          @dependencies[entry[:name]] = entry[:dependencies]
        end
      end

      def module_names
        @modules.keys.sort
      end

      def dependencies_for(module_name)
        @dependencies.fetch(module_name.to_s, [])
      end

      def reachable_from(roots)
        visited = Set.new
        stack = normalize_roots(roots)

        until stack.empty?
          current = stack.pop
          next if visited.include?(current)

          visited << current
          dependencies_for(current).each do |dependency|
            stack << dependency if @modules.key?(dependency)
          end
        end

        visited.to_a.sort
      end

      def prune_for_failures(roots:, failed_modules:)
        failed_names = extract_failed_names(failed_modules).to_set
        reachable = reachable_from(roots)
        memo = {}

        kept = []
        pruned = []

        reachable.each do |module_name|
          failed_dependencies = failed_dependencies_for(module_name, failed_names, memo: memo, visiting: Set.new)
          if failed_dependencies.empty?
            kept << module_name
          else
            pruned << {
              name: module_name,
              failed_dependencies: failed_dependencies
            }
          end
        end

        {
          kept: kept.sort,
          pruned: pruned.sort_by { |entry| entry[:name] }
        }
      end

      private

      def normalize_modules(modules)
        Array(modules).map do |entry|
          hash = entry.is_a?(Hash) ? entry : {}
          name = value_for(hash, :name).to_s
          next if name.empty?

          {
            name: name,
            dependencies: extract_dependencies(hash)
          }
        end.compact
      end

      def normalize_roots(roots)
        Array(roots)
          .map(&:to_s)
          .reject(&:empty?)
          .uniq
          .select { |name| @modules.key?(name) }
      end

      def extract_failed_names(failed_modules)
        Array(failed_modules).map do |entry|
          if entry.is_a?(Hash)
            value_for(entry, :name).to_s
          else
            entry.to_s
          end
        end.reject(&:empty?).uniq
      end

      def failed_dependencies_for(module_name, failed_names, memo:, visiting:)
        return memo[module_name] if memo.key?(module_name)
        return [] unless @modules.key?(module_name)
        return [] if visiting.include?(module_name)

        visiting << module_name
        failed = Set.new

        dependencies_for(module_name).each do |dependency|
          if failed_names.include?(dependency)
            failed << dependency
          elsif @modules.key?(dependency)
            failed_dependencies_for(dependency, failed_names, memo: memo, visiting: visiting).each do |name|
              failed << name
            end
          end
        end

        visiting.delete(module_name)
        memo[module_name] = failed.to_a.sort
      end

      def extract_dependencies(entry)
        explicit_dependencies = value_for(entry, :dependencies)
        if !explicit_dependencies.nil?
          return Array(explicit_dependencies).map(&:to_s).reject(&:empty?).uniq
        end

        instances = Array(value_for(entry, :instances))
        dependencies = instances.map do |instance|
          instance_hash = instance.is_a?(Hash) ? instance : {}
          value_for(instance_hash, :module_name) || value_for(instance_hash, :module)
        end

        dependencies.map(&:to_s).reject(&:empty?).uniq
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
