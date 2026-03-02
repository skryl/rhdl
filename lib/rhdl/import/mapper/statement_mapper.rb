# frozen_string_literal: true

require_relative "expression_mapper"

module RHDL
  module Import
    class Mapper
      class StatementMapper
        include Helpers

        def initialize(expression_mapper:, diagnostics:)
          @expression_mapper = expression_mapper
          @diagnostics = diagnostics
        end

        def map(node, module_name:)
          return nil if node.nil?

          hash = normalize_hash(node)
          kind = value_for(hash, :kind).to_s

          case kind
          when "continuous_assign"
            target = @expression_mapper.map(value_for(hash, :target), module_name: module_name)
            value = @expression_mapper.map(value_for(hash, :value), module_name: module_name)
            return nil unless target && value

            IR::ContinuousAssign.new(
              target: target,
              value: value,
              span: normalize_span(value_for(hash, :span))
            )
          when "blocking_assign"
            target = @expression_mapper.map(value_for(hash, :target), module_name: module_name)
            value = @expression_mapper.map(value_for(hash, :value), module_name: module_name)
            return nil unless target && value

            IR::BlockingAssign.new(
              target: target,
              value: value,
              span: normalize_span(value_for(hash, :span))
            )
          when "nonblocking_assign"
            target = @expression_mapper.map(value_for(hash, :target), module_name: module_name)
            value = @expression_mapper.map(value_for(hash, :value), module_name: module_name)
            return nil unless target && value

            IR::NonBlockingAssign.new(
              target: target,
              value: value,
              span: normalize_span(value_for(hash, :span))
            )
          when "if"
            condition = @expression_mapper.map(value_for(hash, :condition), module_name: module_name)
            return nil unless condition

            IR::IfStatement.new(
              condition: condition,
              then_body: map_list(value_for(hash, :then), module_name: module_name),
              else_body: map_list(value_for(hash, :else), module_name: module_name),
              span: normalize_span(value_for(hash, :span))
            )
          when "case"
            selector = @expression_mapper.map(value_for(hash, :selector), module_name: module_name)
            return nil unless selector

            items = Array(value_for(hash, :items)).filter_map do |item|
              item_hash = normalize_hash(item)
              values = @expression_mapper.map_list(value_for(item_hash, :values), module_name: module_name)
              next if values.empty?

              IR::CaseItem.new(
                values: values,
                body: map_list(value_for(item_hash, :body), module_name: module_name),
                span: normalize_span(value_for(item_hash, :span))
              )
            end

            IR::CaseStatement.new(
              selector: selector,
              items: items,
              default_body: map_list(value_for(hash, :default), module_name: module_name),
              span: normalize_span(value_for(hash, :span))
            )
          when "for"
            range = normalize_hash(value_for(hash, :range))
            range_start = parse_integer_value(value_for(range, :from))
            range_end = parse_integer_value(value_for(range, :to))
            variable = value_for(hash, :var).to_s
            return nil if variable.empty? || range_start.nil? || range_end.nil?

            IR::ForLoop.new(
              variable: variable,
              range_start: range_start,
              range_end: range_end,
              body: map_list(value_for(hash, :body), module_name: module_name),
              span: normalize_span(value_for(hash, :span))
            )
          else
            unsupported_construct!(
              diagnostics: @diagnostics,
              family: :statement,
              construct: kind,
              node: hash,
              module_name: module_name
            )
          end
        end

        def map_list(nodes, module_name:)
          Array(nodes).filter_map { |node| map(node, module_name: module_name) }
        end

        def parse_integer_value(value)
          return value if value.is_a?(Integer)

          if value.is_a?(Hash)
            hash = normalize_hash(value)
            return nil unless value_for(hash, :kind).to_s == "number"

            literal = value_for(hash, :value)
            base = value_for(hash, :base).to_s.strip.downcase
            text = literal.to_s
            return nil if text.empty?

            radix =
              case base
              when "b", "2" then 2
              when "o", "8" then 8
              when "h", "16" then 16
              else 10
              end
            return Integer(text, radix)
          end

          Integer(value)
        rescue ArgumentError, TypeError
          nil
        end
      end
    end
  end
end
