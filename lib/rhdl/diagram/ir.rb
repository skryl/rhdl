# Diagram intermediate representation

require 'json'

require_relative 'edge'
require_relative 'node'
require_relative 'render_dot'

module RHDL
  module Diagram
    class Cluster
      attr_reader :id, :label, :nodes, :clusters

      def initialize(id:, label:)
        @id = id
        @label = label
        @nodes = []
        @clusters = []
      end

      def add_node(node_id)
        @nodes << node_id
      end

      def add_cluster(cluster)
        @clusters << cluster
      end

      def to_h
        {
          id: @id,
          label: @label,
          nodes: @nodes,
          clusters: @clusters.map(&:to_h)
        }
      end
    end

    class IR
      attr_reader :name, :nodes, :edges, :clusters

      def initialize(name: 'diagram')
        @name = name
        @nodes = {}
        @edges = []
        @clusters = []
      end

      def add_node(node)
        @nodes[node.id] = node
        node
      end

      def add_edge(edge)
        @edges << edge
        edge
      end

      def add_cluster(cluster)
        @clusters << cluster
        cluster
      end

      def to_h
        {
          name: @name,
          nodes: @nodes.values.map(&:to_h),
          edges: @edges.map(&:to_h),
          clusters: @clusters.map(&:to_h)
        }
      end

      def to_dot
        RenderDot.generate(self)
      end

      def to_json(*_args)
        JSON.pretty_generate(to_h)
      end
    end
  end
end
