# Gate-level diagram builder

require_relative 'ir'

module RHDL
  module Diagram
    class GateLevelDiagram
      def self.build(gate_ir, bit_blasted: false, collapse_buses: true)
        diagram = IR.new(name: gate_ir.name)
        net_nodes = {}
        net_labels = {}

        input_nodes = add_port_nodes(diagram, gate_ir.inputs, direction: :input, bit_blasted: bit_blasted, collapse_buses: collapse_buses, net_labels: net_labels)
        output_nodes = add_port_nodes(diagram, gate_ir.outputs, direction: :output, bit_blasted: bit_blasted, collapse_buses: collapse_buses, net_labels: net_labels)
        net_nodes.merge!(input_nodes)
        net_nodes.merge!(output_nodes)

        gate_ir.gates.each_with_index do |gate, idx|
          gate_id = Id.for('gate', gate.type.to_s, idx)
          diagram.add_node(Node.new(id: gate_id, kind: :gate, label: gate.type.to_s.upcase, metadata: { gate_type: gate.type }))

          gate.inputs.each do |net|
            from_id = net_node(diagram, net_nodes, net)
            label = net_labels[net]
            diagram.add_edge(Edge.new(from: from_id, to: gate_id, label: label))
          end

          out_id = net_node(diagram, net_nodes, gate.output)
          diagram.add_edge(Edge.new(from: gate_id, to: out_id, label: net_labels[gate.output]))
        end

        gate_ir.dffs.each_with_index do |dff, idx|
          dff_id = Id.for('dff', idx)
          diagram.add_node(Node.new(id: dff_id, kind: :dff, label: 'DFF', metadata: { async_reset: dff.async_reset }))

          add_net_edge(diagram, net_nodes, dff.d, dff_id, net_labels[dff.d])
          add_net_edge(diagram, net_nodes, dff.q, dff_id, net_labels[dff.q], reverse: true)
          add_net_edge(diagram, net_nodes, dff.rst, dff_id, 'RST') if dff.rst
          add_net_edge(diagram, net_nodes, dff.en, dff_id, 'EN') if dff.en
        end

        diagram
      end

      def self.add_port_nodes(diagram, ports, direction:, bit_blasted:, collapse_buses:, net_labels:)
        net_nodes = {}
        ports.sort_by { |name, _| name.to_s }.each do |name, nets|
          width = nets.length
          if bit_blasted || !collapse_buses || width == 1
            nets.each_with_index do |net, idx|
              label = width == 1 ? name.to_s : "#{name}[#{idx}]"
              port_id = Id.for('port', name, direction, idx)
              diagram.add_node(Node.new(id: port_id, kind: :port, label: label, metadata: { direction: direction }))
              net_nodes[net] = port_id
            end
          else
            port_id = Id.for('port', name, direction)
            label = "#{name}[#{width - 1}:0]"
            diagram.add_node(Node.new(id: port_id, kind: :port, label: label, metadata: { direction: direction, width: width }))
            nets.each_with_index do |net, idx|
              net_nodes[net] = port_id
              net_labels[net] = "#{name}[#{idx}]"
            end
          end
        end
        net_nodes
      end

      def self.net_node(diagram, net_nodes, net)
        return net_nodes[net] if net_nodes.key?(net)

        wire_id = Id.for('wire', net)
        diagram.add_node(Node.new(id: wire_id, kind: :wire, label: "n#{net}", metadata: { net: net }))
        net_nodes[net] = wire_id
        wire_id
      end

      def self.add_net_edge(diagram, net_nodes, net, gate_id, label, reverse: false)
        node_id = net_node(diagram, net_nodes, net)
        if reverse
          diagram.add_edge(Edge.new(from: gate_id, to: node_id, label: label))
        else
          diagram.add_edge(Edge.new(from: node_id, to: gate_id, label: label))
        end
      end
    end
  end
end
