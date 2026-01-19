# SVG renderer using Graphviz

require 'open3'

module RHDL
  module Diagram
    class RenderSVG
      def self.render(diagram, format: 'svg')
        return nil unless graphviz_available?

        dot = diagram.to_dot
        stdout, _stderr, status = Open3.capture3('dot', "-T#{format}", stdin_data: dot)
        return nil unless status.success?

        stdout
      end

      def self.graphviz_available?
        system('dot -V > /dev/null 2>&1')
      end
    end
  end
end
