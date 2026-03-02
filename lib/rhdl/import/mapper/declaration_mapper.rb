# frozen_string_literal: true

require_relative "expression_mapper"

module RHDL
  module Import
    class Mapper
      class DeclarationMapper
        include Helpers

        SUPPORTED_KINDS = %w[logic wire reg].freeze

        def initialize(expression_mapper:, diagnostics:)
          @expression_mapper = expression_mapper
          @diagnostics = diagnostics
        end

        def map(node, module_name:)
          return nil if node.nil?

          hash = normalize_hash(node)
          kind = value_for(hash, :kind).to_s

          unless SUPPORTED_KINDS.include?(kind)
            return unsupported_construct!(
              diagnostics: @diagnostics,
              family: :declaration,
              construct: kind,
              node: hash,
              module_name: module_name
            )
          end

          IR::Declaration.new(
            kind: kind,
            name: value_for(hash, :name).to_s,
            width: map_width(value_for(hash, :width), module_name: module_name),
            span: normalize_span(value_for(hash, :span))
          )
        end

        def map_list(nodes, module_name:)
          Array(nodes).filter_map { |node| map(node, module_name: module_name) }
        end

        private

        def map_width(node, module_name:)
          hash = normalize_hash(node)
          return nil if hash.empty?

          msb = @expression_mapper.map(value_for(hash, :msb), module_name: module_name)
          lsb = @expression_mapper.map(value_for(hash, :lsb), module_name: module_name)
          return nil unless msb && lsb

          IR::Range.new(msb: msb, lsb: lsb)
        end
      end
    end
  end
end
