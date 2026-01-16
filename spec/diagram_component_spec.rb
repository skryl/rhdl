require_relative 'spec_helper'
require_relative '../lib/rhdl/diagram'
require_relative '../lib/rhdl/hdl/arithmetic'

RSpec.describe RHDL::Diagram do
  describe '.component' do
    it 'renders deterministic DOT output' do
      component = RHDL::HDL::HalfAdder.new('half_adder')
      dot_a = described_class.component(component).to_dot
      dot_b = described_class.component(component).to_dot
      expect(dot_a).to eq(dot_b)
    end

    it 'includes all ports with labels' do
      component = RHDL::HDL::HalfAdder.new('half_adder')
      diagram = described_class.component(component)

      port_nodes = diagram.nodes.values.select { |node| node.kind == :port }
      labels = port_nodes.map(&:label)

      expect(port_nodes.length).to eq(4)
      expect(labels).to include('a', 'b', 'sum', 'cout')
    end
  end
end
