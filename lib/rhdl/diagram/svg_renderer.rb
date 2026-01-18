# SVG Renderer for generating vector graphics diagrams of HDL components

module RHDL
  module Diagram
    # SVG Renderer for generating vector graphics diagrams
    class SVGRenderer
      COLORS = {
        background: "#ffffff",
        border: "#333333",
        fill: "#f8f9fa",
        header_fill: "#4a90d9",
        header_text: "#ffffff",
        port_input: "#28a745",
        port_output: "#dc3545",
        wire: "#666666",
        text: "#333333",
        subcomponent_fill: "#e9ecef",
        subcomponent_border: "#6c757d"
      }

      def initialize(component, options = {})
        @component = component
        @options = {
          width: 800,
          padding: 40,
          port_height: 25,
          header_height: 50,
          component_min_width: 200,
          subcomponent_scale: 0.8,
          show_subcomponents: true,
          show_values: false
        }.merge(options)
      end

      def render
        lines = []

        # Calculate dimensions
        dims = calculate_dimensions

        # SVG header
        lines << svg_header(dims[:total_width], dims[:total_height])

        # Defs (gradients, markers)
        lines << render_defs

        # Background
        lines << rect(0, 0, dims[:total_width], dims[:total_height],
                     fill: COLORS[:background], stroke: "none")

        # Main component
        lines << render_component(@component, @options[:padding], @options[:padding], dims[:main_width], dims[:main_height])

        # Subcomponents (if enabled)
        if @options[:show_subcomponents]
          subcomponents = get_subcomponents
          unless subcomponents.empty?
            y_offset = @options[:padding] + dims[:main_height] + 30
            lines << text(@options[:padding], y_offset, "Internal Components",
                         font_size: 14, font_weight: "bold")
            y_offset += 20

            subcomponents.each do |name, sub|
              sub_dims = calculate_component_dimensions(sub)
              scaled_width = sub_dims[:width] * @options[:subcomponent_scale]
              scaled_height = sub_dims[:height] * @options[:subcomponent_scale]

              lines << "<g transform=\"translate(#{@options[:padding]}, #{y_offset}) scale(#{@options[:subcomponent_scale]})\">"
              lines << render_component(sub, 0, 0, sub_dims[:width], sub_dims[:height], is_sub: true)
              lines << "</g>"

              y_offset += scaled_height + 20
            end
          end
        end

        # SVG footer
        lines << "</svg>"

        lines.join("\n")
      end

      private

      def svg_header(width, height)
        <<~SVG
          <?xml version="1.0" encoding="UTF-8"?>
          <svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">
        SVG
      end

      def render_defs
        <<~SVG
          <defs>
            <linearGradient id="headerGradient" x1="0%" y1="0%" x2="0%" y2="100%">
              <stop offset="0%" style="stop-color:#5a9fd4"/>
              <stop offset="100%" style="stop-color:#4a90d9"/>
            </linearGradient>
            <marker id="arrowhead" markerWidth="10" markerHeight="7"
                    refX="9" refY="3.5" orient="auto">
              <polygon points="0 0, 10 3.5, 0 7" fill="#{COLORS[:wire]}"/>
            </marker>
            <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
              <feDropShadow dx="2" dy="2" stdDeviation="2" flood-opacity="0.3"/>
            </filter>
          </defs>
        SVG
      end

      def render_component(comp, x, y, width, height, is_sub: false)
        lines = []

        border_color = is_sub ? COLORS[:subcomponent_border] : COLORS[:border]
        fill_color = is_sub ? COLORS[:subcomponent_fill] : COLORS[:fill]

        # Component box with shadow
        lines << "<g filter=\"url(#shadow)\">"
        lines << rect(x, y, width, height,
                     fill: fill_color, stroke: border_color, stroke_width: 2, rx: 5)
        lines << "</g>"

        # Header
        header_h = @options[:header_height]
        lines << rect(x, y, width, header_h,
                     fill: "url(#headerGradient)", stroke: border_color,
                     stroke_width: 2, rx: "5 5 0 0")

        # Component name
        type_name = comp.class.name.split('::').last
        lines << text(x + width/2, y + 20, comp.name,
                     fill: COLORS[:header_text], font_size: 14, font_weight: "bold", anchor: "middle")
        lines << text(x + width/2, y + 38, "(#{type_name})",
                     fill: COLORS[:header_text], font_size: 11, anchor: "middle")

        # Ports
        port_h = @options[:port_height]
        inputs = comp.inputs.keys
        outputs = comp.outputs.keys

        # Input ports (left side)
        inputs.each_with_index do |name, i|
          port_y = y + header_h + 15 + (i * port_h)
          wire = comp.inputs[name]

          # Wire line coming in
          lines << line(x - 30, port_y + 8, x, port_y + 8,
                       stroke: COLORS[:port_input], stroke_width: 2, marker_end: "url(#arrowhead)")

          # Port circle
          lines << circle(x, port_y + 8, 5, fill: COLORS[:port_input], stroke: border_color)

          # Port label
          width_str = wire.width > 1 ? "[#{wire.width}]" : ""
          val_str = @options[:show_values] ? " = #{wire.get}" : ""
          lines << text(x + 10, port_y + 12, "#{name}#{width_str}#{val_str}",
                       fill: COLORS[:text], font_size: 11)
        end

        # Output ports (right side)
        outputs.each_with_index do |name, i|
          port_y = y + header_h + 15 + (i * port_h)
          wire = comp.outputs[name]

          # Port circle
          lines << circle(x + width, port_y + 8, 5, fill: COLORS[:port_output], stroke: border_color)

          # Wire line going out
          lines << line(x + width, port_y + 8, x + width + 30, port_y + 8,
                       stroke: COLORS[:port_output], stroke_width: 2, marker_end: "url(#arrowhead)")

          # Port label
          width_str = wire.width > 1 ? "[#{wire.width}]" : ""
          val_str = @options[:show_values] ? " = #{wire.get}" : ""
          label = "#{name}#{width_str}#{val_str}"
          lines << text(x + width - 10, port_y + 12, label,
                       fill: COLORS[:text], font_size: 11, anchor: "end")
        end

        lines.join("\n")
      end

      def calculate_dimensions
        main = calculate_component_dimensions(@component)

        total_height = main[:height] + (@options[:padding] * 2)

        if @options[:show_subcomponents]
          subcomponents = get_subcomponents
          unless subcomponents.empty?
            total_height += 50  # "Internal Components" header
            subcomponents.each do |_, sub|
              sub_dims = calculate_component_dimensions(sub)
              total_height += (sub_dims[:height] * @options[:subcomponent_scale]) + 20
            end
          end
        end

        {
          main_width: main[:width],
          main_height: main[:height],
          total_width: main[:width] + (@options[:padding] * 2) + 60,  # Extra for wires
          total_height: total_height
        }
      end

      def calculate_component_dimensions(comp)
        port_count = [comp.inputs.size, comp.outputs.size].max
        port_count = [port_count, 1].max

        height = @options[:header_height] + (port_count * @options[:port_height]) + 30
        width = [@options[:component_min_width], calculate_min_width(comp)].max

        { width: width, height: height }
      end

      def calculate_min_width(comp)
        # Calculate based on longest port names
        input_max = comp.inputs.keys.map { |n| n.to_s.length }.max || 0
        output_max = comp.outputs.keys.map { |n| n.to_s.length }.max || 0

        (input_max + output_max + 10) * 8  # Approximate character width
      end

      def get_subcomponents
        subs = @component.instance_variable_get(:@subcomponents) || {}

        [:@pc, :@acc, :@alu, :@decoder, :@memory, :@sp].each do |var|
          val = @component.instance_variable_get(var)
          if val.respond_to?(:inputs) && val.respond_to?(:outputs)
            subs[var.to_s.delete('@').to_sym] ||= val
          end
        end

        subs
      end

      # SVG element helpers
      def rect(x, y, width, height, fill: "none", stroke: "black", stroke_width: 1, rx: 0)
        rx_attr = rx.is_a?(String) ? "rx=\"#{rx.split.first}\"" : "rx=\"#{rx}\""
        "<rect x=\"#{x}\" y=\"#{y}\" width=\"#{width}\" height=\"#{height}\" " \
        "fill=\"#{fill}\" stroke=\"#{stroke}\" stroke-width=\"#{stroke_width}\" #{rx_attr}/>"
      end

      def circle(cx, cy, r, fill: "none", stroke: "black", stroke_width: 1)
        "<circle cx=\"#{cx}\" cy=\"#{cy}\" r=\"#{r}\" " \
        "fill=\"#{fill}\" stroke=\"#{stroke}\" stroke-width=\"#{stroke_width}\"/>"
      end

      def line(x1, y1, x2, y2, stroke: "black", stroke_width: 1, marker_end: nil)
        marker = marker_end ? "marker-end=\"#{marker_end}\"" : ""
        "<line x1=\"#{x1}\" y1=\"#{y1}\" x2=\"#{x2}\" y2=\"#{y2}\" " \
        "stroke=\"#{stroke}\" stroke-width=\"#{stroke_width}\" #{marker}/>"
      end

      def text(x, y, content, fill: "black", font_size: 12, font_weight: "normal", anchor: "start")
        "<text x=\"#{x}\" y=\"#{y}\" fill=\"#{fill}\" font-size=\"#{font_size}\" " \
        "font-weight=\"#{font_weight}\" text-anchor=\"#{anchor}\" font-family=\"monospace\">#{content}</text>"
      end
    end
  end
end
