# Netlist-level diagram builder

require_relative 'ir'
require_relative 'hierarchy'

module RHDL
  module Diagram
    class NetlistDiagram
      def self.build(component)
        diagram = IR.new(name: component.name)
        scope = HierarchyDiagram::Scope.new(component, depth: :all)

        components = scope.components
        components = [component] if components.empty?
        components.each do |comp|
          node_id = Id.for('component', comp.name)
          label = "#{short_class_name(comp.class)}\n#{comp.name}"
          diagram.add_node(Node.new(id: node_id, kind: :component, label: label))
        end

        scope.connections.each do |edge|
          diagram.add_edge(Edge.new(from: edge.from, to: edge.to, label: edge.label))
        end

        diagram
      end

      def self.short_class_name(klass)
        klass.name.split('::').last
      end
    end
  end
end
