# HDL Circuit Diagram Renderer
# Generates ASCII/Unicode circuit diagrams for HDL components

module RHDL
  module Diagram
    # Renders circuit diagrams for HDL components
    class Renderer
      # Box-drawing characters
      CHARS = {
        unicode: {
          h: "\u2500",      # horizontal
          v: "\u2502",      # vertical
          tl: "\u250C",     # top-left
          tr: "\u2510",     # top-right
          bl: "\u2514",     # bottom-left
          br: "\u2518",     # bottom-right
          lj: "\u251C",     # left junction
          rj: "\u2524",     # right junction
          tj: "\u252C",     # top junction
          bj: "\u2534",     # bottom junction
          cross: "\u253C",  # cross
          arrow_r: "\u25B6", # right arrow
          arrow_l: "\u25C0", # left arrow
          dot: "\u25CF",    # filled circle (connection point)
          hdash: "\u2504",  # dashed horizontal
          vdash: "\u2506",  # dashed vertical
          double_h: "\u2550", # double horizontal
          double_v: "\u2551", # double vertical
          double_tl: "\u2554", # double top-left
          double_tr: "\u2557", # double top-right
          double_bl: "\u255A", # double bottom-left
          double_br: "\u255D", # double bottom-right
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
            sub_renderer = Renderer.new(sub, **@options.merge(indent: 4, min_width: 15))
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
            sub_renderer = Renderer.new(sub, **@options)
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
          if val.respond_to?(:inputs) && val.respond_to?(:outputs)
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
  end
end
