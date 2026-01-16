# HDL Circuit Diagram Generator
# Generates pretty ASCII/Unicode circuit diagrams for any component

module RHDL
  module HDL
    # Renders circuit diagrams for HDL components
    class DiagramRenderer
      # Box-drawing characters
      CHARS = {
        unicode: {
          h: "\u2500",      # ─ horizontal
          v: "\u2502",      # │ vertical
          tl: "\u250C",     # ┌ top-left
          tr: "\u2510",     # ┐ top-right
          bl: "\u2514",     # └ bottom-left
          br: "\u2518",     # ┘ bottom-right
          lj: "\u251C",     # ├ left junction
          rj: "\u2524",     # ┤ right junction
          tj: "\u252C",     # ┬ top junction
          bj: "\u2534",     # ┴ bottom junction
          cross: "\u253C",  # ┼ cross
          arrow_r: "\u25B6", # ▶ right arrow
          arrow_l: "\u25C0", # ◀ left arrow
          dot: "\u25CF",    # ● filled circle (connection point)
          hdash: "\u2504",  # ┄ dashed horizontal
          vdash: "\u2506",  # ┆ dashed vertical
          double_h: "\u2550", # ═ double horizontal
          double_v: "\u2551", # ║ double vertical
          double_tl: "\u2554", # ╔ double top-left
          double_tr: "\u2557", # ╗ double top-right
          double_bl: "\u255A", # ╚ double bottom-left
          double_br: "\u255D", # ╝ double bottom-right
        },
        ascii: {
          h: "-",
          v: "|",
          tl: "+",
          tr: "+",
          bl: "+",
          br: "+",
          lj: "+",
          rj: "+",
          tj: "+",
          bj: "+",
          cross: "+",
          arrow_r: ">",
          arrow_l: "<",
          dot: "*",
          hdash: "-",
          vdash: ":",
          double_h: "=",
          double_v: "#",
          double_tl: "#",
          double_tr: "#",
          double_bl: "#",
          double_br: "#",
        }
      }

      attr_reader :component, :options

      def initialize(component, **options)
        @component = component
        @options = {
          style: :unicode,
          show_values: false,
          show_widths: true,
          min_width: 20,
          max_width: 80,
          compact: false,
          show_subcomponents: true,
          indent: 0,
          color: false
        }.merge(options)
        @chars = CHARS[@options[:style]]
      end

      # Generate a simple block diagram of a component
      def render_block
        lines = []

        inputs = @component.inputs.keys
        outputs = @component.outputs.keys

        # Calculate dimensions
        max_input_len = inputs.map { |n| port_label(n, :input).length }.max || 0
        max_output_len = outputs.map { |n| port_label(n, :output).length }.max || 0
        name_len = @component.name.length + 4

        inner_width = [@options[:min_width], name_len, max_input_len + max_output_len + 8].max
        inner_width = [inner_width, @options[:max_width]].min

        port_rows = [inputs.length, outputs.length].max
        port_rows = [port_rows, 1].max

        # Build the diagram
        indent = " " * @options[:indent]
        wire_len = 4

        # Top border
        lines << "#{indent}#{' ' * (wire_len + 1)}#{c(:tl)}#{c(:h) * inner_width}#{c(:tr)}"

        # Component name (centered in top area)
        name_line = @component.name.center(inner_width)
        lines << "#{indent}#{' ' * (wire_len + 1)}#{c(:v)}#{name_line}#{c(:v)}"

        # Component type
        type_name = @component.class.name.split('::').last
        type_line = "(#{type_name})".center(inner_width)
        lines << "#{indent}#{' ' * (wire_len + 1)}#{c(:v)}#{type_line}#{c(:v)}"

        # Separator
        lines << "#{indent}#{' ' * (wire_len + 1)}#{c(:lj)}#{c(:h) * inner_width}#{c(:rj)}"

        # Port rows
        port_rows.times do |i|
          in_port = inputs[i]
          out_port = outputs[i]

          # Input side
          if in_port
            in_label = port_label(in_port, :input)
            in_wire = "#{c(:h) * wire_len}#{c(:arrow_r)}"
            in_text = in_label.ljust((inner_width / 2) - 1)
          else
            in_wire = " " * (wire_len + 1)
            in_text = " " * ((inner_width / 2) - 1)
          end

          # Output side
          if out_port
            out_label = port_label(out_port, :output)
            out_wire = "#{c(:arrow_r)}#{c(:h) * wire_len}"
            out_text = out_label.rjust((inner_width / 2) - 1)
          else
            out_wire = " " * (wire_len + 1)
            out_text = " " * ((inner_width / 2) - 1)
          end

          content = "#{in_text} #{out_text}"
          content = content[0, inner_width] if content.length > inner_width
          content = content.ljust(inner_width)

          junction_l = in_port ? c(:lj) : c(:v)
          junction_r = out_port ? c(:rj) : c(:v)

          lines << "#{indent}#{in_wire}#{junction_l}#{content}#{junction_r}#{out_wire}"
        end

        # Bottom border
        lines << "#{indent}#{' ' * (wire_len + 1)}#{c(:bl)}#{c(:h) * inner_width}#{c(:br)}"

        lines.join("\n")
      end

      # Generate a detailed schematic with subcomponents
      def render_schematic
        lines = []

        # Header
        lines << render_header
        lines << ""

        # Component interface
        lines << "Interface:"
        lines << render_block
        lines << ""

        # Subcomponents (if any and enabled)
        subcomponents = get_subcomponents
        if @options[:show_subcomponents] && !subcomponents.empty?
          lines << ""
          lines << "Internal Components:"
          lines << c(:h) * 60

          subcomponents.each do |name, sub|
            lines << ""
            lines << "  #{c(:dot)} #{name}: #{sub.class.name.split('::').last}"

            # Render mini block for subcomponent
            sub_renderer = DiagramRenderer.new(sub, **@options.merge(indent: 4, min_width: 15))
            lines << sub_renderer.render_block
          end

          lines << ""
          lines << c(:h) * 60
        end

        # Internal signals (if any)
        signals = @component.internal_signals
        unless signals.empty?
          lines << ""
          lines << "Internal Signals:"
          signals.each do |name, wire|
            val_str = @options[:show_values] ? " = #{wire.get}" : ""
            width_str = wire.width > 1 ? "[#{wire.width}]" : ""
            lines << "  #{c(:hdash)} #{name}#{width_str}#{val_str}"
          end
        end

        lines.join("\n")
      end

      # Generate hierarchical diagram showing component tree
      def render_hierarchy(depth: 0, max_depth: 3)
        lines = []
        indent = "  " * depth
        prefix = depth > 0 ? "#{c(:lj)}#{c(:h)} " : ""

        # Component header
        type_name = @component.class.name.split('::').last
        port_summary = "(#{@component.inputs.size} in, #{@component.outputs.size} out)"
        lines << "#{indent}#{prefix}#{@component.name} [#{type_name}] #{port_summary}"

        # Show ports at leaf level or when compact
        if depth == max_depth || @options[:compact]
          @component.inputs.each do |name, wire|
            width_str = wire.width > 1 ? "[#{wire.width}]" : ""
            val_str = @options[:show_values] ? " = #{wire.get}" : ""
            lines << "#{indent}  #{c(:arrow_r)} #{name}#{width_str}#{val_str}"
          end
          @component.outputs.each do |name, wire|
            width_str = wire.width > 1 ? "[#{wire.width}]" : ""
            val_str = @options[:show_values] ? " = #{wire.get}" : ""
            lines << "#{indent}  #{c(:arrow_l)} #{name}#{width_str}#{val_str}"
          end
        end

        # Recursively render subcomponents
        if depth < max_depth
          subcomponents = get_subcomponents
          subcomponents.each do |name, sub|
            sub_renderer = DiagramRenderer.new(sub, **@options)
            lines << sub_renderer.render_hierarchy(depth: depth + 1, max_depth: max_depth)
          end
        end

        lines.join("\n")
      end

      # Generate DOT (Graphviz) format for external rendering
      def to_dot
        lines = []

        lines << "digraph #{sanitize_name(@component.name)} {"
        lines << "  rankdir=LR;"
        lines << "  node [shape=record, fontname=\"Courier\"];"
        lines << "  edge [fontname=\"Courier\", fontsize=10];"
        lines << ""

        # Generate the main component node
        lines << generate_dot_node(@component, "main")

        # Generate subcomponent nodes
        subcomponents = get_subcomponents
        subcomponents.each_with_index do |(name, sub), idx|
          lines << generate_dot_node(sub, "sub_#{idx}")
        end

        # Add a cluster for the component
        lines << ""
        lines << "  subgraph cluster_main {"
        lines << "    label=\"#{@component.name}\";"
        lines << "    style=rounded;"
        lines << "    color=blue;"

        subcomponents.each_with_index do |(name, sub), idx|
          lines << "    sub_#{idx};"
        end

        lines << "  }"

        lines << "}"
        lines.join("\n")
      end

      # Generate SVG diagram using embedded SVG generation (no external tools)
      def to_svg
        SVGRenderer.new(@component, @options).render
      end

      private

      def c(name)
        @chars[name]
      end

      def port_label(name, type)
        wire = type == :input ? @component.inputs[name] : @component.outputs[name]
        return name.to_s unless wire

        width_str = @options[:show_widths] && wire.width > 1 ? "[#{wire.width}]" : ""
        val_str = @options[:show_values] ? "=#{wire.get}" : ""

        "#{name}#{width_str}#{val_str}"
      end

      def render_header
        type_name = @component.class.name.split('::').last
        "#{c(:double_h) * 3} #{@component.name} (#{type_name}) #{c(:double_h) * 3}"
      end

      def get_subcomponents
        # Try to get @subcomponents instance variable
        subs = @component.instance_variable_get(:@subcomponents) || {}

        # Also look for common subcomponent patterns
        [:@pc, :@acc, :@alu, :@decoder, :@memory, :@sp].each do |var|
          val = @component.instance_variable_get(var)
          if val.is_a?(SimComponent)
            subs[var.to_s.delete('@').to_sym] ||= val
          end
        end

        subs
      end

      def sanitize_name(name)
        name.to_s.gsub(/[^a-zA-Z0-9_]/, '_')
      end

      def generate_dot_node(comp, id)
        inputs_str = comp.inputs.map { |n, w| "<#{n}>#{n}[#{w.width}]" }.join("|")
        outputs_str = comp.outputs.map { |n, w| "<#{n}>#{n}[#{w.width}]" }.join("|")

        label = "{{#{inputs_str}}|#{comp.name}\\n(#{comp.class.name.split('::').last})|{#{outputs_str}}}"
        "  #{id} [label=\"#{label}\"];"
      end
    end

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
        [
          %(<?xml version="1.0" encoding="UTF-8"?>),
          %(<svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">)
        ].join("\n")
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
          if val.is_a?(SimComponent)
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

    # Extension methods for SimComponent
    module DiagramMethods
      # Generate a block diagram of this component
      def to_diagram(**options)
        DiagramRenderer.new(self, **options).render_block
      end

      # Generate a detailed schematic with subcomponents
      def to_schematic(**options)
        DiagramRenderer.new(self, **options).render_schematic
      end

      # Generate a hierarchy tree view
      def to_hierarchy(**options)
        DiagramRenderer.new(self, **options).render_hierarchy(**options)
      end

      # Generate DOT format for Graphviz
      def to_dot(**options)
        DiagramRenderer.new(self, **options).to_dot
      end

      # Generate SVG diagram
      def to_svg(**options)
        DiagramRenderer.new(self, **options).to_svg
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
