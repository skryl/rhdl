# frozen_string_literal: true

module RHDL
  module Import
    module IR
      module Serializable
        def serialize(value)
          return nil if value.nil?

          case value
          when Array
            value.map { |entry| serialize(entry) }
          when Hash
            value.each_with_object({}) do |(key, inner), memo|
              memo[key] = serialize(inner)
            end
          else
            value.respond_to?(:to_h) ? value.to_h : value
          end
        end
      end

      class Program < Struct.new(:schema_version, :modules, :diagnostics, keyword_init: true)
        include Serializable

        def initialize(schema_version:, modules:, diagnostics:)
          super(schema_version: schema_version, modules: Array(modules), diagnostics: Array(diagnostics))
        end

        def to_h
          {
            schema_version: schema_version,
            modules: serialize(modules),
            diagnostics: serialize(diagnostics)
          }
        end
      end

      class Span < Struct.new(:source_id, :source_path, :line, :column, :end_line, :end_column, keyword_init: true)
        include Serializable

        def to_h
          {
            source_id: source_id,
            source_path: source_path,
            line: line,
            column: column,
            end_line: end_line,
            end_column: end_column
          }
        end
      end

      class Module < Struct.new(:name, :source_id, :span, :ports, :parameters, :declarations, :statements, :processes, :instances, keyword_init: true)
        include Serializable

        def initialize(name:, source_id:, span:, ports:, parameters:, declarations:, statements:, processes:, instances:)
          super(
            name: name,
            source_id: source_id,
            span: span,
            ports: Array(ports),
            parameters: Array(parameters),
            declarations: Array(declarations),
            statements: Array(statements),
            processes: Array(processes),
            instances: Array(instances)
          )
        end

        def to_h
          {
            name: name,
            source_id: source_id,
            span: serialize(span),
            ports: serialize(ports),
            parameters: serialize(parameters),
            declarations: serialize(declarations),
            statements: serialize(statements),
            processes: serialize(processes),
            instances: serialize(instances)
          }
        end
      end

      class Port < Struct.new(:name, :direction, :width, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            name: name,
            direction: direction,
            width: serialize(width),
            span: serialize(span)
          }
        end
      end

      class Parameter < Struct.new(:name, :default, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            name: name,
            default: serialize(self.default),
            span: serialize(span)
          }
        end
      end

      class Declaration < Struct.new(:kind, :name, :width, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            kind: kind,
            name: name,
            width: serialize(width),
            span: serialize(span)
          }
        end
      end

      class Range < Struct.new(:msb, :lsb, keyword_init: true)
        include Serializable

        def to_h
          {
            msb: serialize(msb),
            lsb: serialize(lsb)
          }
        end
      end

      class Process < Struct.new(:domain, :sensitivity, :statements, :span, :intent, :origin, :provenance, keyword_init: true)
        include Serializable

        def initialize(domain:, sensitivity:, statements:, span: nil, intent: nil, origin: nil, provenance: nil)
          super(
            domain: domain,
            sensitivity: Array(sensitivity),
            statements: Array(statements),
            span: span,
            intent: intent,
            origin: origin,
            provenance: provenance
          )
        end

        def to_h
          hash = {
            domain: domain,
            sensitivity: serialize(sensitivity),
            statements: serialize(statements),
            span: serialize(span)
          }
          hash[:intent] = intent unless intent.nil?
          hash[:origin] = origin unless origin.nil?
          hash[:provenance] = serialize(provenance) unless provenance.nil?
          hash
        end
      end

      class SensitivityEvent < Struct.new(:edge, :signal, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            edge: edge,
            signal: serialize(signal),
            span: serialize(span)
          }
        end
      end

      class Instance < Struct.new(:name, :module_name, :parameter_overrides, :connections, :span, keyword_init: true)
        include Serializable

        def initialize(name:, module_name:, parameter_overrides:, connections:, span: nil)
          super(
            name: name,
            module_name: module_name,
            parameter_overrides: Array(parameter_overrides),
            connections: Array(connections),
            span: span
          )
        end

        def to_h
          {
            name: name,
            module_name: module_name,
            parameter_overrides: serialize(parameter_overrides),
            connections: serialize(connections),
            span: serialize(span)
          }
        end
      end

      class ParameterOverride < Struct.new(:name, :value, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            name: name,
            value: serialize(value),
            span: serialize(span)
          }
        end
      end

      class Connection < Struct.new(:port, :signal, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            port: port,
            signal: serialize(signal),
            span: serialize(span)
          }
        end
      end

      class ContinuousAssign < Struct.new(:target, :value, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            kind: "continuous_assign",
            target: serialize(target),
            value: serialize(value),
            span: serialize(span)
          }
        end
      end

      class BlockingAssign < Struct.new(:target, :value, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            kind: "blocking_assign",
            target: serialize(target),
            value: serialize(value),
            span: serialize(span)
          }
        end
      end

      class NonBlockingAssign < Struct.new(:target, :value, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            kind: "nonblocking_assign",
            target: serialize(target),
            value: serialize(value),
            span: serialize(span)
          }
        end
      end

      class IfStatement < Struct.new(:condition, :then_body, :else_body, :span, keyword_init: true)
        include Serializable

        def initialize(condition:, then_body:, else_body:, span: nil)
          super(condition: condition, then_body: Array(then_body), else_body: Array(else_body), span: span)
        end

        def to_h
          {
            kind: "if",
            condition: serialize(condition),
            then_body: serialize(then_body),
            else_body: serialize(else_body),
            span: serialize(span)
          }
        end
      end

      class CaseItem < Struct.new(:values, :body, :span, keyword_init: true)
        include Serializable

        def initialize(values:, body:, span: nil)
          super(values: Array(values), body: Array(body), span: span)
        end

        def to_h
          {
            values: serialize(values),
            body: serialize(body),
            span: serialize(span)
          }
        end
      end

      class CaseStatement < Struct.new(:selector, :items, :default_body, :span, :qualifier, :origin, :provenance, keyword_init: true)
        include Serializable

        def initialize(selector:, items:, default_body:, span: nil, qualifier: nil, origin: nil, provenance: nil)
          super(
            selector: selector,
            items: Array(items),
            default_body: Array(default_body),
            span: span,
            qualifier: qualifier,
            origin: origin,
            provenance: provenance
          )
        end

        def to_h
          hash = {
            kind: "case",
            selector: serialize(selector),
            items: serialize(items),
            default_body: serialize(default_body),
            span: serialize(span)
          }
          hash[:qualifier] = qualifier unless qualifier.nil?
          hash[:origin] = origin unless origin.nil?
          hash[:provenance] = serialize(provenance) unless provenance.nil?
          hash
        end
      end

      class ForLoop < Struct.new(:variable, :range_start, :range_end, :body, :span, keyword_init: true)
        include Serializable

        def initialize(variable:, range_start:, range_end:, body:, span: nil)
          super(
            variable: variable.to_s,
            range_start: range_start,
            range_end: range_end,
            body: Array(body),
            span: span
          )
        end

        def to_h
          {
            kind: "for",
            variable: variable,
            range: {
              from: range_start,
              to: range_end
            },
            body: serialize(body),
            span: serialize(span)
          }
        end
      end

      class Identifier < Struct.new(:name, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            kind: "identifier",
            name: name,
            span: serialize(span)
          }
        end
      end

      class NumberLiteral < Struct.new(:value, :base, :width, :signed, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            kind: "number",
            value: value,
            base: base,
            width: width,
            signed: signed,
            span: serialize(span)
          }
        end
      end

      class UnaryExpression < Struct.new(:operator, :operand, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            kind: "unary",
            operator: operator,
            operand: serialize(operand),
            span: serialize(span)
          }
        end
      end

      class BinaryExpression < Struct.new(:operator, :left, :right, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            kind: "binary",
            operator: operator,
            left: serialize(left),
            right: serialize(right),
            span: serialize(span)
          }
        end
      end

      class TernaryExpression < Struct.new(:condition, :true_expr, :false_expr, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            kind: "ternary",
            condition: serialize(condition),
            true_expr: serialize(true_expr),
            false_expr: serialize(false_expr),
            span: serialize(span)
          }
        end
      end

      class Concatenation < Struct.new(:parts, :span, keyword_init: true)
        include Serializable

        def initialize(parts:, span: nil)
          super(parts: Array(parts), span: span)
        end

        def to_h
          {
            kind: "concat",
            parts: serialize(parts),
            span: serialize(span)
          }
        end
      end

      class Replication < Struct.new(:count, :value, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            kind: "replication",
            count: serialize(count),
            value: serialize(value),
            span: serialize(span)
          }
        end
      end

      class IndexExpression < Struct.new(:base, :index, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            kind: "index",
            base: serialize(base),
            index: serialize(index),
            span: serialize(span)
          }
        end
      end

      class SliceExpression < Struct.new(:base, :msb, :lsb, :span, keyword_init: true)
        include Serializable

        def to_h
          {
            kind: "slice",
            base: serialize(base),
            msb: serialize(msb),
            lsb: serialize(lsb),
            span: serialize(span)
          }
        end
      end
    end
  end
end
