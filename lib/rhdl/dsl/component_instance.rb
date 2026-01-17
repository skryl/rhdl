# frozen_string_literal: true

module RHDL
  module DSL
    # Component instance
    class ComponentInstance
      attr_reader :name, :component_type, :port_map, :generic_map

      def initialize(name, component_type, port_map: {}, generic_map: {})
        @name = name
        @component_type = component_type
        @port_map = port_map
        @generic_map = generic_map
      end

      def to_vhdl
        lines = []
        lines << "#{name}: #{component_type}"

        unless generic_map.empty?
          generics = generic_map.map { |k, v| "#{k} => #{v}" }
          lines << "  generic map(#{generics.join(', ')})"
        end

        ports = port_map.map do |k, v|
          val = v.respond_to?(:to_vhdl) ? v.to_vhdl : v.to_s
          "#{k} => #{val}"
        end
        lines << "  port map(#{ports.join(', ')});"

        lines.join("\n")
      end

      def to_verilog
        lines = []

        # In Verilog: module_name #(.param(value)) instance_name (.port(signal), ...);
        if generic_map.empty?
          lines << "#{component_type} #{name} ("
        else
          params = generic_map.map { |k, v| ".#{k}(#{v})" }
          lines << "#{component_type} #(#{params.join(', ')}) #{name} ("
        end

        ports = port_map.map do |k, v|
          val = v.respond_to?(:to_verilog) ? v.to_verilog : v.to_s
          ".#{k}(#{val})"
        end
        lines << "  #{ports.join(', ')}"
        lines << ");"

        lines.join("\n")
      end
    end
  end
end
