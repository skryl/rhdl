# Diagram extension methods for HDL Component
# Adds to_diagram, to_svg, and other diagram-related methods

module RHDL
  module Diagram
    # Extension methods for Component
    module Methods
      # Generate a block diagram of this component
      def to_diagram(**options)
        Renderer.new(self, **options).render_block
      end

      # Generate a detailed schematic with subcomponents
      def to_schematic(**options)
        Renderer.new(self, **options).render_schematic
      end

      # Generate a hierarchy tree view
      def to_hierarchy(**options)
        Renderer.new(self, **options).render_hierarchy(**options)
      end

      # Generate DOT format for Graphviz
      def to_dot(**options)
        Renderer.new(self, **options).to_dot
      end

      # Generate SVG diagram
      def to_svg(**options)
        Renderer.new(self, **options).to_svg
      end

      # Print diagram to stdout
      def print_diagram(**options)
        puts to_diagram(**options)
      end

      # Print schematic to stdout
      def print_schematic(**options)
        puts to_schematic(**options)
      end

      # Print hierarchy to stdout
      def print_hierarchy(**options)
        puts to_hierarchy(**options)
      end

      # Save SVG to file
      def save_svg(filename, **options)
        File.write(filename, to_svg(**options))
      end

      # Save DOT to file
      def save_dot(filename, **options)
        File.write(filename, to_dot(**options))
      end
    end
  end
end
