# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::Codegen::CIRCT::Flatten do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  it 'flattens simple instance hierarchies into a single module' do
    child = ir::ModuleOp.new(
      name: 'child',
      ports: [
        ir::Port.new(name: :a, direction: :in, width: 8),
        ir::Port.new(name: :y, direction: :out, width: 8)
      ],
      nets: [],
      regs: [],
      assigns: [
        ir::Assign.new(
          target: :y,
          expr: ir::BinaryOp.new(
            op: :+,
            left: ir::Signal.new(name: :a, width: 8),
            right: ir::Literal.new(value: 1, width: 8),
            width: 8
          )
        )
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )

    top = ir::ModuleOp.new(
      name: 'top',
      ports: [
        ir::Port.new(name: :a, direction: :in, width: 8),
        ir::Port.new(name: :y, direction: :out, width: 8)
      ],
      nets: [],
      regs: [],
      assigns: [],
      processes: [],
      instances: [
        ir::Instance.new(
          name: 'u',
          module_name: 'child',
          connections: [
            ir::PortConnection.new(port_name: :a, signal: :a, direction: :in, width: 8),
            ir::PortConnection.new(port_name: :y, signal: :y, direction: :out, width: 8)
          ],
          parameters: {}
        )
      ],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )

    flat = described_class.to_flat_module([top, child], top: 'top')

    expect(flat.name).to eq('top')
    expect(flat.instances).to eq([])
    expect(flat.ports.map { |port| [port.name.to_s, port.direction.to_s] }).to eq(
      [%w[a in], %w[y out]]
    )
    expect(flat.nets.map { |net| net.name.to_s }).to include('u__a', 'u__y')

    child_assign = flat.assigns.find { |assign| assign.target.to_s == 'u__y' }
    expect(child_assign).not_to be_nil
    expect(child_assign.expr).to be_a(ir::BinaryOp)
    expect(child_assign.expr.left).to be_a(ir::Signal)
    expect(child_assign.expr.left.name.to_s).to eq('u__a')

    input_bridge = flat.assigns.find { |assign| assign.target.to_s == 'u__a' }
    expect(input_bridge).not_to be_nil
    expect(input_bridge.expr).to be_a(ir::Signal)
    expect(input_bridge.expr.name.to_s).to eq('a')

    output_bridge = flat.assigns.find { |assign| assign.target.to_s == 'y' }
    expect(output_bridge).not_to be_nil
    expect(output_bridge.expr).to be_a(ir::Signal)
    expect(output_bridge.expr.name.to_s).to eq('u__y')
  end
end
