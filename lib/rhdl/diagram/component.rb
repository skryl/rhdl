# Component-level diagram builder

require_relative 'ir'

module RHDL
  module Diagram
    class ComponentDiagram
      def self.build(component)
        diagram = IR.new(name: component.name)
        component_id = Id.for('component', component.name)
        diagram.add_node(Node.new(id: component_id, kind: :component, label: component.name))

        inputs = component.inputs.sort_by { |name, _| name.to_s }
        outputs = component.outputs.sort_by { |name, _| name.to_s }

        inputs.each do |name, wire|
          port_id = Id.for('port', component.name, name, 'in')
          label = label_for_port(name, wire.width)
          diagram.add_node(Node.new(id: port_id, kind: :port, label: label, metadata: { direction: :input }))
          diagram.add_edge(Edge.new(from: port_id, to: component_id))
        end

        outputs.each do |name, wire|
          port_id = Id.for('port', component.name, name, 'out')
          label = label_for_port(name, wire.width)
          diagram.add_node(Node.new(id: port_id, kind: :port, label: label, metadata: { direction: :output }))
          diagram.add_edge(Edge.new(from: component_id, to: port_id))
        end

        diagram
      end

      def self.label_for_port(name, width)
        base = name.to_s
        return base if width == 1

        "#{base}[#{width - 1}:0]"
      end
    end
  end
end
