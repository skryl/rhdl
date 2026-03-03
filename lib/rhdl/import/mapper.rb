# frozen_string_literal: true

require_relative "ir"
require_relative "mapper/helpers"
require_relative "mapper/expression_mapper"
require_relative "mapper/statement_mapper"
require_relative "mapper/declaration_mapper"

module RHDL
  module Import
    class Mapper
      include Helpers

      class << self
        def map(payload)
          new(payload).map
        end
      end

      def initialize(payload)
        @payload = normalize_hash(payload)
        @diagnostics = normalize_diagnostics(value_for(@payload, :diagnostics))
        @expression_mapper = ExpressionMapper.new(diagnostics: @diagnostics)
        @statement_mapper = StatementMapper.new(expression_mapper: @expression_mapper, diagnostics: @diagnostics)
        @declaration_mapper = DeclarationMapper.new(expression_mapper: @expression_mapper, diagnostics: @diagnostics)
      end

      def map
        IR::Program.new(
          schema_version: integer_or_default(value_for(@payload, :schema_version), 1),
          modules: map_modules,
          diagnostics: @diagnostics
        )
      end

      private

      def map_modules
        design = normalize_hash(value_for(@payload, :design))
        Array(value_for(design, :modules)).filter_map { |module_node| map_module(module_node) }
      end

      def map_module(module_node)
        hash = normalize_hash(module_node)
        name = value_for(hash, :name).to_s
        return nil if name.empty?

        IR::Module.new(
          name: name,
          source_id: value_for(hash, :source_id),
          span: normalize_span(value_for(hash, :span)),
          ports: map_ports(value_for(hash, :ports), module_name: name),
          parameters: map_parameters(value_for(hash, :parameters), module_name: name),
          declarations: @declaration_mapper.map_list(value_for(hash, :declarations), module_name: name),
          statements: @statement_mapper.map_list(value_for(hash, :statements), module_name: name),
          processes: map_processes(value_for(hash, :processes), module_name: name),
          instances: map_instances(value_for(hash, :instances), module_name: name)
        )
      end

      def map_parameters(parameters, module_name:)
        Array(parameters).map do |parameter|
          hash = normalize_hash(parameter)
          IR::Parameter.new(
            name: value_for(hash, :name).to_s,
            default: @expression_mapper.map(value_for(hash, :default), module_name: module_name),
            span: normalize_span(value_for(hash, :span))
          )
        end
      end

      def map_ports(ports, module_name:)
        Array(ports).filter_map do |port|
          hash = normalize_hash(port)
          name = value_for(hash, :name).to_s
          next if name.empty?

          IR::Port.new(
            name: name,
            direction: normalize_port_direction(value_for(hash, :direction)),
            width: map_port_width(value_for(hash, :width), module_name: module_name),
            span: normalize_span(value_for(hash, :span))
          )
        end
      end

      def map_processes(processes, module_name:)
        Array(processes).filter_map do |process|
          hash = normalize_hash(process)
          kind = value_for(hash, :kind).to_s

          unless %w[always initial].include?(kind)
            unsupported_construct!(
              diagnostics: @diagnostics,
              family: :process,
              construct: kind,
              node: hash,
              module_name: module_name
            )
            next
          end

          IR::Process.new(
            domain: normalize_process_domain(value_for(hash, :domain), kind: kind),
            sensitivity: kind == "initial" ? [] : map_sensitivity(value_for(hash, :sensitivity), module_name: module_name),
            statements: @statement_mapper.map_list(value_for(hash, :statements), module_name: module_name),
            span: normalize_span(value_for(hash, :span)),
            intent: optional_string(value_for(hash, :intent)),
            origin: optional_string(value_for(hash, :origin)),
            provenance: normalize_metadata_hash(value_for(hash, :provenance))
          )
        end
      end

      def map_sensitivity(events, module_name:)
        Array(events).filter_map do |event|
          hash = normalize_hash(event)
          signal = @expression_mapper.map(value_for(hash, :signal), module_name: module_name)
          next unless signal

          IR::SensitivityEvent.new(
            edge: value_for(hash, :edge).to_s,
            signal: signal,
            span: normalize_span(value_for(hash, :span))
          )
        end
      end

      def map_instances(instances, module_name:)
        Array(instances).map do |instance|
          hash = normalize_hash(instance)
          IR::Instance.new(
            name: value_for(hash, :name).to_s,
            module_name: value_for(hash, :module_name).to_s,
            parameter_overrides: map_parameter_overrides(value_for(hash, :parameter_overrides), module_name: module_name),
            connections: map_connections(value_for(hash, :connections), module_name: module_name),
            span: normalize_span(value_for(hash, :span))
          )
        end
      end

      def map_parameter_overrides(overrides, module_name:)
        Array(overrides).map do |override|
          hash = normalize_hash(override)
          IR::ParameterOverride.new(
            name: value_for(hash, :name).to_s,
            value: @expression_mapper.map(value_for(hash, :value), module_name: module_name),
            span: normalize_span(value_for(hash, :span))
          )
        end
      end

      def map_connections(connections, module_name:)
        Array(connections).map do |connection|
          hash = normalize_hash(connection)
          signal = @expression_mapper.map(value_for(hash, :signal), module_name: module_name)
          IR::Connection.new(
            port: value_for(hash, :port).to_s,
            signal: signal,
            span: normalize_span(value_for(hash, :span))
          )
        end
      end

      def map_port_width(node, module_name:)
        return nil if node.nil?

        hash = normalize_hash(node)
        return @expression_mapper.map(node, module_name: module_name) if hash.empty?

        if hash.key?(:msb) || hash.key?("msb")
          msb = @expression_mapper.map(value_for(hash, :msb), module_name: module_name)
          lsb = @expression_mapper.map(value_for(hash, :lsb), module_name: module_name)
          return nil unless msb && lsb

          return IR::Range.new(msb: msb, lsb: lsb)
        end

        @expression_mapper.map(hash, module_name: module_name)
      end

      def normalize_port_direction(direction)
        case direction.to_s.downcase
        when "input", "in"
          "input"
        when "output", "out"
          "output"
        when "inout"
          "inout"
        else
          "input"
        end
      end

      def normalize_process_domain(value, kind:)
        normalized = value.to_s
        return "initial" if kind == "initial" && normalized.empty?
        normalized.empty? ? "combinational" : normalized
      end

      def normalize_diagnostics(diagnostics)
        Array(diagnostics).map { |diagnostic| deep_symbolize(diagnostic) }
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, inner), memo|
            memo[key.to_sym] = deep_symbolize(inner)
          end
        when Array
          value.map { |inner| deep_symbolize(inner) }
        else
          value
        end
      end
    end
  end
end
