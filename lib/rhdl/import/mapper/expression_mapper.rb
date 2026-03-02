# frozen_string_literal: true

require_relative "../ir"
require_relative "helpers"

module RHDL
  module Import
    class Mapper
      class ExpressionMapper
        include Helpers

        def initialize(diagnostics:)
          @diagnostics = diagnostics
        end

        def map(node, module_name:)
          return nil if node.nil?

          hash = normalize_hash(node)
          kind = value_for(hash, :kind).to_s

          case kind
          when "identifier"
            IR::Identifier.new(
              name: value_for(hash, :name).to_s,
              span: normalize_span(value_for(hash, :span))
            )
          when "number", "integer", "literal"
            IR::NumberLiteral.new(
              value: value_for(hash, :value),
              base: value_for(hash, :base),
              width: value_for(hash, :width),
              signed: value_for(hash, :signed),
              span: normalize_span(value_for(hash, :span))
            )
          when "unary"
            operand = map(value_for(hash, :operand), module_name: module_name)
            return nil unless operand

            IR::UnaryExpression.new(
              operator: value_for(hash, :operator).to_s,
              operand: operand,
              span: normalize_span(value_for(hash, :span))
            )
          when "binary"
            left = map(value_for(hash, :left), module_name: module_name)
            right = map(value_for(hash, :right), module_name: module_name)
            return nil unless left && right

            IR::BinaryExpression.new(
              operator: value_for(hash, :operator).to_s,
              left: left,
              right: right,
              span: normalize_span(value_for(hash, :span))
            )
          when "ternary"
            condition = map(value_for(hash, :condition), module_name: module_name)
            true_expr = map(value_for(hash, :true_expr), module_name: module_name)
            false_expr = map(value_for(hash, :false_expr), module_name: module_name)
            return nil unless condition && true_expr && false_expr

            IR::TernaryExpression.new(
              condition: condition,
              true_expr: true_expr,
              false_expr: false_expr,
              span: normalize_span(value_for(hash, :span))
            )
          when "concat"
            parts = map_list(value_for(hash, :parts), module_name: module_name)

            IR::Concatenation.new(
              parts: parts,
              span: normalize_span(value_for(hash, :span))
            )
          when "replication"
            count = map(value_for(hash, :count), module_name: module_name)
            value = map(value_for(hash, :value), module_name: module_name)
            return nil unless count && value

            IR::Replication.new(
              count: count,
              value: value,
              span: normalize_span(value_for(hash, :span))
            )
          when "index"
            base = map(value_for(hash, :base), module_name: module_name)
            index = map(value_for(hash, :index), module_name: module_name)
            return nil unless base && index

            IR::IndexExpression.new(
              base: base,
              index: index,
              span: normalize_span(value_for(hash, :span))
            )
          when "slice"
            base = map(value_for(hash, :base), module_name: module_name)
            msb = map(value_for(hash, :msb), module_name: module_name)
            lsb = map(value_for(hash, :lsb), module_name: module_name)
            return nil unless base && msb && lsb

            IR::SliceExpression.new(
              base: base,
              msb: msb,
              lsb: lsb,
              span: normalize_span(value_for(hash, :span))
            )
          else
            unsupported_construct!(
              diagnostics: @diagnostics,
              family: :expression,
              construct: kind,
              node: hash,
              module_name: module_name
            )
          end
        end

        def map_list(nodes, module_name:)
          Array(nodes).filter_map { |node| map(node, module_name: module_name) }
        end
      end
    end
  end
end
