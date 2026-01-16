# DOT renderer for diagram IR

module RHDL
  module Diagram
    class RenderDot
      SHAPES = {
        component: 'box',
        gate: 'ellipse',
        dff: 'box',
        port: 'plaintext',
        wire: 'circle'
      }.freeze

      def self.generate(diagram)
        lines = []
        lines << %(digraph "#{diagram.name}" {)
        lines << '  rankdir=LR;'
        lines << '  node [fontname="Helvetica"];'
        lines << '  edge [fontname="Helvetica"];'

        cluster_nodes = render_clusters(lines, diagram.clusters)

        diagram.nodes.values.sort_by(&:id).each do |node|
          next if cluster_nodes.include?(node.id)

          lines << format_node(node)
        end

        diagram.edges.sort_by { |edge| [edge.from, edge.to, edge.label.to_s] }.each do |edge|
          lines << format_edge(edge)
        end

        lines << '}'
        lines.join("\n")
      end

      def self.render_clusters(lines, clusters, indent: 1)
        cluster_nodes = []
        clusters.sort_by(&:id).each do |cluster|
          prefix = '  ' * indent
          lines << %(#{prefix}subgraph "cluster_#{cluster.id}" {)
          lines << %(#{prefix}  label="#{escape(cluster.label)}";)
          cluster.nodes.sort.each do |node_id|
            cluster_nodes << node_id
            lines << "#{prefix}  #{dot_id(node_id)};"
          end
          cluster_nodes.concat(render_clusters(lines, cluster.clusters, indent: indent + 1))
          lines << "#{prefix}}"
        end
        cluster_nodes
      end

      def self.format_node(node)
        shape = SHAPES.fetch(node.kind, 'box')
        extra = node.kind == :dff ? ' style="rounded"' : ''
        %(  #{dot_id(node.id)} [label="#{escape(node.label)}" shape=#{shape}#{extra}];)
      end

      def self.format_edge(edge)
        if edge.label
          %(  #{dot_id(edge.from)} -> #{dot_id(edge.to)} [label="#{escape(edge.label)}"];)
        else
          %(  #{dot_id(edge.from)} -> #{dot_id(edge.to)};)
        end
      end

      def self.dot_id(value)
        %("#{escape(value)}")
      end

      def self.escape(value)
        value.to_s.gsub('"', '\"')
      end
    end
  end
end
