# Diagram generation entry points

require_relative 'diagram/component'
require_relative 'diagram/gate_level'
require_relative 'diagram/hierarchy'
require_relative 'diagram/netlist'
require_relative 'diagram/render_svg'
require_relative 'diagram/renderer'
require_relative 'diagram/svg_renderer'
require_relative 'diagram/methods'

module RHDL
  module Diagram
    module Id
      def self.for(*parts)
        parts.map(&:to_s).join(':')
      end
    end

    def self.component(component)
      ComponentDiagram.build(component)
    end

    def self.hierarchy(component, depth: 1)
      HierarchyDiagram.build(component, depth: depth)
    end

    def self.netlist(component)
      NetlistDiagram.build(component)
    end

    def self.gate_level(gate_ir, bit_blasted: false, collapse_buses: true)
      GateLevelDiagram.build(gate_ir, bit_blasted: bit_blasted, collapse_buses: collapse_buses)
    end

    def self.collect_components(component)
      components = []
      queue = [component]
      until queue.empty?
        current = queue.shift
        components << current
        subs = current.instance_variable_get(:@subcomponents) || {}
        subs.values.each { |sub| queue << sub }
      end
      components
    end
  end
end
