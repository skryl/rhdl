# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for generating circuit diagrams
      class DiagramTask < Task
        def run
          if options[:clean]
            clean
          elsif options[:all]
            generate_all
          else
            generate_single
          end
        end

        # Generate diagrams for all components
        def generate_all
          require 'rhdl/hdl'
          require 'rhdl/export'
          require 'rhdl/diagram'

          mode = options[:mode] || 'all'
          modes_to_run = mode == 'all' ? Config::DIAGRAM_MODES : [mode]

          modes_to_run.each do |m|
            puts "Generating #{m} diagrams..."
            base_dir = File.join(Config.diagrams_dir, m)
            Config::CATEGORIES.each { |c| ensure_dir(File.join(base_dir, c)) }

            components_to_use = m == 'gate' ? Config::GATE_LEVEL_COMPONENTS : Config.hdl_components.keys

            components_to_use.each do |name|
              creator = Config.hdl_components[name]
              next unless creator

              begin
                component = creator.call
                case m
                when 'component'
                  generate_component_diagram(name, component, base_dir)
                when 'hierarchical'
                  generate_hierarchical_diagram(name, component, base_dir)
                when 'gate'
                  generate_gate_level_diagram(name, component, base_dir)
                end
                puts_ok(name)
              rescue => e
                puts_error("#{name}: #{e.message}")
              end
            end
          end

          generate_readme
          puts "\nDiagrams generated in: #{Config.diagrams_dir}"
        end

        # Generate diagram for a single component
        def generate_single
          component_ref = options[:component]
          raise ArgumentError, "Component reference required" unless component_ref

          require 'rhdl/hdl'
          require 'rhdl/diagram'

          component_class = component_ref.split('::').inject(Object) { |mod, name| mod.const_get(name) }
          component = component_class.new(component_ref.downcase)

          diagram = case options[:level]
                    when 'component'
                      RHDL::Diagram.component(component)
                    when 'hierarchy'
                      RHDL::Diagram.hierarchy(component, depth: options[:depth])
                    when 'netlist'
                      RHDL::Diagram.netlist(component)
                    when 'gate'
                      require 'rhdl/export'
                      components = RHDL::Diagram.collect_components(component)
                      gate_ir = RHDL::Gates::Lower.from_components(components, name: component.name)
                      RHDL::Diagram.gate_level(gate_ir, bit_blasted: options[:bit_blasted])
                    else
                      raise ArgumentError, "Unknown level: #{options[:level]}"
                    end

          out_dir = options[:out] || 'diagrams'
          ensure_dir(out_dir)
          base_name = "#{component.name}_#{options[:level]}"

          case options[:format]
          when 'dot'
            File.write(File.join(out_dir, "#{base_name}.dot"), diagram.to_dot)
          when 'svg', 'png'
            output = RHDL::Diagram::RenderSVG.render(diagram, format: options[:format])
            if output
              File.write(File.join(out_dir, "#{base_name}.#{options[:format]}"), output)
            else
              dot_path = File.join(out_dir, "#{base_name}.dot")
              File.write(dot_path, diagram.to_dot)
              warn "Graphviz not available; wrote #{dot_path} instead."
            end
          else
            raise ArgumentError, "Unknown format: #{options[:format]}"
          end

          puts "Diagram saved to: #{out_dir}/#{base_name}.#{options[:format]}"
        end

        # Clean all generated diagrams
        def clean
          Config::DIAGRAM_MODES.each do |mode|
            mode_dir = File.join(Config.diagrams_dir, mode)
            if Dir.exist?(mode_dir)
              FileUtils.rm_rf(mode_dir)
              puts "Cleaned: #{mode_dir}"
            end
          end
          readme = File.join(Config.diagrams_dir, 'README.md')
          FileUtils.rm_f(readme) if File.exist?(readme)
          puts "Diagrams cleaned."
        end

        # Generate a component-level diagram (simple block view)
        def generate_component_diagram(name, component, base_dir)
          subdir = File.dirname(name)
          full_subdir = File.join(base_dir, subdir)
          ensure_dir(full_subdir)
          base_path = File.join(base_dir, name)

          # Generate ASCII block diagram
          txt_content = []
          txt_content << "=" * 60
          txt_content << "Component: #{component.name}"
          txt_content << "Type: #{component.class.name.split('::').last}"
          txt_content << "=" * 60
          txt_content << ""
          txt_content << component.to_diagram
          File.write("#{base_path}.txt", txt_content.join("\n"))

          # Generate SVG (simple block view)
          component.save_svg("#{base_path}.svg", show_subcomponents: false)

          # Generate DOT
          component.save_dot("#{base_path}.dot")
        end

        # Generate a hierarchical diagram (with subcomponents)
        def generate_hierarchical_diagram(name, component, base_dir)
          subdir = File.dirname(name)
          full_subdir = File.join(base_dir, subdir)
          ensure_dir(full_subdir)
          base_path = File.join(base_dir, name)

          # Generate ASCII schematic with subcomponents
          txt_content = []
          txt_content << "=" * 60
          txt_content << "Component: #{component.name}"
          txt_content << "Type: #{component.class.name.split('::').last}"
          txt_content << "=" * 60
          txt_content << ""
          txt_content << component.to_schematic(show_subcomponents: true)
          txt_content << ""
          txt_content << "Hierarchy:"
          txt_content << "-" * 40
          txt_content << component.to_hierarchy(max_depth: 3)
          File.write("#{base_path}.txt", txt_content.join("\n"))

          # Generate SVG with subcomponents
          component.save_svg("#{base_path}.svg", show_subcomponents: true)

          # Generate DOT
          component.save_dot("#{base_path}.dot")
        end

        # Generate a gate-level diagram
        def generate_gate_level_diagram(name, component, base_dir)
          subdir = File.dirname(name)
          full_subdir = File.join(base_dir, subdir)
          ensure_dir(full_subdir)
          base_path = File.join(base_dir, name)

          # Lower to gate-level IR
          ir = RHDL::Export::Structure::Lower.from_components([component], name: component.name)

          # Build gate-level diagram
          diagram = RHDL::Diagram.gate_level(ir)

          # Generate DOT format
          dot_content = diagram.to_dot
          File.write("#{base_path}.dot", dot_content)

          # Generate text summary
          txt_content = []
          txt_content << "=" * 60
          txt_content << "Gate-Level: #{component.name}"
          txt_content << "Type: #{component.class.name.split('::').last}"
          txt_content << "=" * 60
          txt_content << ""
          txt_content << "Gates: #{ir.gates.length}"
          txt_content << "DFFs: #{ir.dffs.length}"
          txt_content << "Nets: #{ir.net_count}"
          txt_content << ""
          txt_content << "Inputs:"
          ir.inputs.each { |n, nets| txt_content << "  #{n}[#{nets.length}]" }
          txt_content << ""
          txt_content << "Outputs:"
          ir.outputs.each { |n, nets| txt_content << "  #{n}[#{nets.length}]" }
          txt_content << ""
          txt_content << "Gate Types:"
          gate_counts = ir.gates.group_by(&:type).transform_values(&:length)
          gate_counts.each { |type, count| txt_content << "  #{type}: #{count}" }
          File.write("#{base_path}.txt", txt_content.join("\n"))
        end

        # Generate README.md for the diagrams directory
        def generate_readme
          diagrams_dir = Config.diagrams_dir
          readme = []
          readme << "# RHDL Component Diagrams"
          readme << ""
          readme << "This directory contains circuit diagrams for all HDL components in RHDL,"
          readme << "organized into three visualization modes."
          readme << ""
          readme << "## Diagram Modes"
          readme << ""
          readme << "### Component (`component/`)"
          readme << "Simple block diagrams showing component interface (inputs/outputs)."
          readme << "Best for understanding what a component does at a high level."
          readme << ""
          readme << "### Hierarchical (`hierarchical/`)"
          readme << "Detailed schematics showing internal subcomponents and hierarchy."
          readme << "Best for understanding how complex components are built from simpler ones."
          readme << ""
          readme << "### Gate (`gate/`)"
          readme << "Gate-level netlist diagrams showing primitive logic gates and flip-flops."
          readme << "Only available for components that support gate-level lowering."
          readme << "Best for understanding the actual hardware implementation."
          readme << ""
          readme << "## File Formats"
          readme << ""
          readme << "Each component has up to three diagram files:"
          readme << "- `.txt` - ASCII/Unicode text diagram for terminal viewing"
          readme << "- `.svg` - Scalable vector graphics for web/document viewing"
          readme << "- `.dot` - Graphviz DOT format for custom rendering"
          readme << ""
          readme << "## Rendering DOT Files"
          readme << ""
          readme << "To render DOT files as PNG images using Graphviz:"
          readme << "```bash"
          readme << "dot -Tpng diagrams/gate/arithmetic/full_adder.dot -o full_adder.png"
          readme << "```"
          readme << ""
          readme << "## Components by Category"
          readme << ""

          category_names = {
            'gates' => 'Logic Gates',
            'sequential' => 'Sequential Components',
            'arithmetic' => 'Arithmetic Components',
            'combinational' => 'Combinational Components',
            'memory' => 'Memory Components',
            'cpu' => 'CPU Components'
          }

          Config::CATEGORIES.each do |category|
            readme << "### #{category_names[category]}"
            readme << ""

            path = File.join(diagrams_dir, 'component', category)
            if Dir.exist?(path)
              files = Dir.glob(File.join(path, '*.txt')).sort
              files.each do |f|
                basename = File.basename(f, '.txt')
                gate_level = Config::GATE_LEVEL_COMPONENTS.include?("#{category}/#{basename}")
                gate_link = gate_level ? ", [Gate](gate/#{category}/#{basename}.dot)" : ""
                readme << "- **#{basename}**: [Component](component/#{category}/#{basename}.txt), [Hierarchical](hierarchical/#{category}/#{basename}.txt)#{gate_link}"
              end
            end
            readme << ""
          end

          readme << "## Regenerating Diagrams"
          readme << ""
          readme << "```bash"
          readme << "# Using the CLI"
          readme << "rhdl diagram --all"
          readme << ""
          readme << "# Using rake"
          readme << "rake diagrams:generate"
          readme << "```"
          readme << ""
          readme << "---"
          readme << "*Generated by RHDL Circuit Diagram Generator*"

          File.write(File.join(diagrams_dir, 'README.md'), readme.join("\n"))
        end
      end
    end
  end
end
