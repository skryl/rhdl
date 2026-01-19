# Hierarchical diagram builder

require_relative 'ir'
require_relative 'component'

module RHDL
  module Diagram
    class HierarchyDiagram
      def self.build(component, depth: 1)
        diagram = IR.new(name: component.name)
        top_cluster = Cluster.new(id: Id.for('cluster', component.name), label: component.name)
        diagram.add_cluster(top_cluster)

        scope = Scope.new(component, depth: depth)
        scope.components.each do |comp|
          node_id = Id.for('component', comp.name)
          label = "#{comp.name}\n(#{short_class_name(comp.class)})"
          diagram.add_node(Node.new(id: node_id, kind: :component, label: label))
          cluster = scope.cluster_for(comp)
          cluster.add_node(node_id) if cluster
        end

        add_port_nodes(diagram, top_cluster, component)
        add_edges(diagram, scope)
        diagram
      end

      def self.short_class_name(klass)
        klass.name.split('::').last
      end

      def self.add_port_nodes(diagram, cluster, component)
        component.inputs.sort_by { |name, _| name.to_s }.each do |name, wire|
          port_id = Id.for('port', component.name, name, 'in')
          label = ComponentDiagram.label_for_port(name, wire.width)
          diagram.add_node(Node.new(id: port_id, kind: :port, label: label, metadata: { direction: :input }))
          cluster.add_node(port_id)
        end

        component.outputs.sort_by { |name, _| name.to_s }.each do |name, wire|
          port_id = Id.for('port', component.name, name, 'out')
          label = ComponentDiagram.label_for_port(name, wire.width)
          diagram.add_node(Node.new(id: port_id, kind: :port, label: label, metadata: { direction: :output }))
          cluster.add_node(port_id)
        end
      end

      def self.add_edges(diagram, scope)
        connections = scope.connections
        connections.sort_by { |edge| [edge.from, edge.to, edge.label.to_s] }.each do |edge|
          diagram.add_edge(edge)
        end
      end

      class Scope
        attr_reader :components

        def initialize(component, depth:)
          @component = component
          @depth = depth
          @components = []
          @clusters = {}
          build_scope
        end

        def cluster_for(component)
          @clusters[component]
        end

        def connections
          owner_map = wire_owner_map
          edges = []

          owner_map[:inputs].each do |wire, info|
            driver = wire.driver
            next unless driver

            from_owner = owner_map[:outputs][driver]
            to_owner = info
            next unless from_owner && to_owner

            edges << Edge.new(from: from_owner[:node_id], to: to_owner[:node_id], label: label_for_wire(wire))
          end

          edges
        end

        private

        def build_scope
          @clusters[@component] = Cluster.new(id: Id.for('cluster', @component.name), label: @component.name)
          collect_components(@component, @depth, @clusters[@component])
        end

        def collect_components(component, depth, cluster)
          subs = subcomponents(component)
          subs.each do |sub|
            @components << sub
            sub_cluster = cluster
            @clusters[sub] = sub_cluster
            if depth == :all || depth.to_i > 1
              sub_cluster = Cluster.new(id: Id.for('cluster', sub.name), label: sub.name)
              cluster.add_cluster(sub_cluster)
              @clusters[sub] = sub_cluster
            end
            next_depth = depth == :all ? :all : depth.to_i - 1
            collect_components(sub, next_depth, sub_cluster) if next_depth == :all || next_depth.to_i > 0
          end
        end

        def subcomponents(component)
          subs = component.instance_variable_get(:@subcomponents) || {}
          subs.values
        end

        def wire_owner_map
          inputs = {}
          outputs = {}

          scope_components = @components + [@component]
          scope_components.each do |comp|
            comp.inputs.each do |name, wire|
              inputs[wire] = { node_id: Id.for('component', comp.name), port: name, wire: wire }
            end
            comp.outputs.each do |name, wire|
              outputs[wire] = { node_id: Id.for('component', comp.name), port: name, wire: wire }
            end
          end

          @component.inputs.each do |name, wire|
            inputs[wire] = { node_id: Id.for('port', @component.name, name, 'in'), port: name, wire: wire }
            outputs[wire] = { node_id: Id.for('port', @component.name, name, 'in'), port: name, wire: wire }
          end
          @component.outputs.each do |name, wire|
            outputs[wire] = { node_id: Id.for('port', @component.name, name, 'out'), port: name, wire: wire }
            inputs[wire] = { node_id: Id.for('port', @component.name, name, 'out'), port: name, wire: wire }
          end

          { inputs: inputs, outputs: outputs }
        end

        def label_for_wire(wire)
          width = wire.width
          return nil if width == 1

          "[#{width - 1}:0]"
        end
      end
    end
  end
end
