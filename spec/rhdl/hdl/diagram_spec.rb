require 'spec_helper'

RSpec.describe RHDL::HDL::DiagramRenderer do
  describe 'Basic gate diagrams' do
    let(:and_gate) { RHDL::HDL::AndGate.new("my_and") }

    it 'renders a block diagram for a simple gate' do
      diagram = and_gate.to_diagram
      expect(diagram).to include("my_and")
      expect(diagram).to include("AndGate")
      expect(diagram).to include("a0")
      expect(diagram).to include("a1")
      expect(diagram).to include("y")
    end

    it 'renders with ASCII style' do
      diagram = and_gate.to_diagram(style: :ascii)
      expect(diagram).to include("+")  # ASCII corners
      expect(diagram).to include("-")  # ASCII horizontal
      expect(diagram).not_to include("\u250C")  # No unicode
    end

    it 'renders with Unicode style' do
      diagram = and_gate.to_diagram(style: :unicode)
      expect(diagram).to include("\u2500")  # Unicode horizontal line
    end

    it 'shows signal values when enabled' do
      and_gate.set_input(:a0, 1)
      and_gate.set_input(:a1, 1)
      and_gate.propagate

      diagram = and_gate.to_diagram(show_values: true)
      expect(diagram).to include("=1")
    end
  end

  describe 'Multi-bit component diagrams' do
    let(:alu) { RHDL::HDL::ALU.new("test_alu", width: 8) }

    it 'shows port widths' do
      diagram = alu.to_diagram(show_widths: true)
      expect(diagram).to include("[8]")  # 8-bit width
      expect(diagram).to include("[4]")  # 4-bit op
    end

    it 'renders all ALU ports' do
      diagram = alu.to_diagram
      # Inputs
      expect(diagram).to include("a")
      expect(diagram).to include("b")
      expect(diagram).to include("op")
      expect(diagram).to include("cin")
      # Outputs
      expect(diagram).to include("result")
      expect(diagram).to include("cout")
      expect(diagram).to include("zero")
      expect(diagram).to include("negative")
      expect(diagram).to include("overflow")
    end
  end

  describe 'Schematic rendering' do
    let(:alu) { RHDL::HDL::ALU.new("alu") }

    it 'renders a schematic with header' do
      schematic = alu.to_schematic
      expect(schematic).to include("alu")
      expect(schematic).to include("Interface:")
    end
  end

  describe 'Hierarchy rendering' do
    let(:cpu) { RHDL::HDL::CPU::Datapath.new("test_cpu") }

    it 'shows component hierarchy' do
      hierarchy = cpu.to_hierarchy(max_depth: 1)
      expect(hierarchy).to include("test_cpu")
      expect(hierarchy).to include("Datapath")
    end

    it 'shows subcomponents' do
      hierarchy = cpu.to_hierarchy(max_depth: 2)
      # CPU datapath has these subcomponents
      expect(hierarchy).to include("pc")
      expect(hierarchy).to include("acc")
      expect(hierarchy).to include("alu")
      expect(hierarchy).to include("decoder")
    end
  end

  describe 'DOT format export' do
    let(:adder) { RHDL::HDL::FullAdder.new("fa") }

    it 'generates valid DOT syntax' do
      dot = adder.to_dot
      expect(dot).to include("digraph")
      expect(dot).to include("rankdir=LR")
      expect(dot).to include("node [shape=record")
      expect(dot).to include("fa")
    end

    it 'includes port information' do
      dot = adder.to_dot
      expect(dot).to match(/label=.*a.*b.*cin.*sum.*cout/)
    end
  end

  describe 'SVG format export' do
    let(:gate) { RHDL::HDL::OrGate.new("or1") }

    it 'generates valid SVG' do
      svg = gate.to_svg
      expect(svg).to include('<?xml version="1.0"')
      expect(svg).to include('<svg')
      expect(svg).to include('</svg>')
    end

    it 'includes component name' do
      svg = gate.to_svg
      expect(svg).to include("or1")
    end

    it 'includes port visualization' do
      svg = gate.to_svg
      expect(svg).to include("a0")
      expect(svg).to include("a1")
      expect(svg).to include("y")
    end
  end

  describe 'Complex component diagrams' do
    let(:cpu) { RHDL::HDL::CPU::Datapath.new("cpu") }

    it 'renders CPU block diagram' do
      diagram = cpu.to_diagram
      expect(diagram).to include("cpu")
      expect(diagram).to include("Datapath")
      expect(diagram).to include("clk")
      expect(diagram).to include("rst")
    end

    it 'renders CPU schematic with subcomponents' do
      schematic = cpu.to_schematic(show_subcomponents: true)
      expect(schematic).to include("Internal Components")
      expect(schematic).to include("pc")
      expect(schematic).to include("alu")
    end

    it 'generates CPU SVG diagram' do
      svg = cpu.to_svg(show_subcomponents: true)
      expect(svg).to include('<svg')
      expect(svg).to include('cpu')
    end
  end

  describe 'Convenience methods' do
    let(:gate) { RHDL::HDL::NotGate.new("inv") }

    it 'provides print_diagram method' do
      expect { gate.print_diagram }.to output(/inv/).to_stdout
    end

    it 'provides print_schematic method' do
      expect { gate.print_schematic }.to output(/Interface/).to_stdout
    end

    it 'provides print_hierarchy method' do
      expect { gate.print_hierarchy }.to output(/inv/).to_stdout
    end
  end

  describe 'File output methods' do
    let(:alu) { RHDL::HDL::ALU.new("alu") }
    let(:svg_file) { '/tmp/test_diagram.svg' }
    let(:dot_file) { '/tmp/test_diagram.dot' }

    after do
      File.delete(svg_file) if File.exist?(svg_file)
      File.delete(dot_file) if File.exist?(dot_file)
    end

    it 'saves SVG to file' do
      alu.save_svg(svg_file)
      expect(File.exist?(svg_file)).to be true
      content = File.read(svg_file)
      expect(content).to include('<svg')
    end

    it 'saves DOT to file' do
      alu.save_dot(dot_file)
      expect(File.exist?(dot_file)).to be true
      content = File.read(dot_file)
      expect(content).to include('digraph')
    end
  end

  describe 'Edge cases' do
    it 'handles components with no inputs' do
      # Create a simple component with only outputs
      class OutputOnlyComponent < RHDL::HDL::SimComponent
        def setup_ports
          output :out1
          output :out2
        end
      end

      comp = OutputOnlyComponent.new("out_only")
      diagram = comp.to_diagram
      expect(diagram).to include("out_only")
      expect(diagram).to include("out1")
    end

    it 'handles components with no outputs' do
      # Create a simple component with only inputs
      class InputOnlyComponent < RHDL::HDL::SimComponent
        def setup_ports
          input :in1
          input :in2
        end
      end

      comp = InputOnlyComponent.new("in_only")
      diagram = comp.to_diagram
      expect(diagram).to include("in_only")
      expect(diagram).to include("in1")
    end

    it 'handles long port names' do
      class LongNameComponent < RHDL::HDL::SimComponent
        def setup_ports
          input :very_long_input_name_here
          output :extremely_long_output_name
        end
      end

      comp = LongNameComponent.new("long_names")
      diagram = comp.to_diagram
      expect(diagram).to include("long_names")
    end
  end
end

RSpec.describe RHDL::HDL::SVGRenderer do
  let(:gate) { RHDL::HDL::AndGate.new("and1") }
  let(:renderer) { RHDL::HDL::SVGRenderer.new(gate) }

  it 'renders valid SVG structure' do
    svg = renderer.render
    expect(svg).to match(/<\?xml/)
    expect(svg).to match(/<svg.*xmlns.*>/)
    expect(svg).to match(/<\/svg>/)
  end

  it 'includes defs section with gradients' do
    svg = renderer.render
    expect(svg).to include('<defs>')
    expect(svg).to include('linearGradient')
    expect(svg).to include('</defs>')
  end

  it 'includes port circles' do
    svg = renderer.render
    expect(svg).to include('<circle')
  end

  it 'includes connecting lines' do
    svg = renderer.render
    expect(svg).to include('<line')
  end
end
