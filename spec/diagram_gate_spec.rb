require_relative 'spec_helper'
require_relative '../lib/rhdl/diagram'
require_relative '../lib/rhdl/export/structural/lower'
require_relative '../lib/rhdl/hdl/gates'
require_relative '../lib/rhdl/hdl/sequential'

RSpec.describe RHDL::Diagram do
  describe '.gate_level' do
    let(:gate_ir) do
      and_gate = RHDL::HDL::AndGate.new('and1')
      dff = RHDL::HDL::DFlipFlop.new('dff1')
      RHDL::Export::Structural::Lower.from_components([and_gate, dff], name: 'gate_test')
    end

    it 'creates nodes for gates and DFFs' do
      diagram = described_class.gate_level(gate_ir)
      gate_nodes = diagram.nodes.values.select { |node| node.kind == :gate }
      dff_nodes = diagram.nodes.values.select { |node| node.kind == :dff }

      expect(gate_nodes.length).to eq(gate_ir.gates.length)
      expect(dff_nodes.length).to eq(gate_ir.dffs.length)
    end

    it 'emits edges for gate outputs' do
      diagram = described_class.gate_level(gate_ir)
      gate_ids = gate_ir.gates.each_with_index.map { |gate, idx| RHDL::Diagram::Id.for('gate', gate.type.to_s, idx) }
      from_ids = diagram.edges.map(&:from)

      gate_ids.each do |gate_id|
        expect(from_ids).to include(gate_id)
      end
    end

    it 'renders SVG when Graphviz is available' do
      diagram = described_class.gate_level(gate_ir)
      unless RHDL::Diagram::RenderSVG.graphviz_available?
        skip 'Graphviz not available'
      end

      svg = RHDL::Diagram::RenderSVG.render(diagram, format: 'svg')
      expect(svg).to be_a(String)
      expect(svg.strip).not_to be_empty
    end
  end
end
