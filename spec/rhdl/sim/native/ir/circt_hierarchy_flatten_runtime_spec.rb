# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CIRCT hierarchical runtime flattening' do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  def build_hierarchical_package
    child = ir::ModuleOp.new(
      name: 'child',
      ports: [
        ir::Port.new(name: :a, direction: :in, width: 1),
        ir::Port.new(name: :y, direction: :out, width: 1)
      ],
      nets: [],
      regs: [],
      assigns: [
        ir::Assign.new(
          target: :y,
          expr: ir::UnaryOp.new(
            op: :'~',
            operand: ir::Signal.new(name: :a, width: 1),
            width: 1
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
        ir::Port.new(name: :a, direction: :in, width: 1),
        ir::Port.new(name: :y, direction: :out, width: 1)
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
            ir::PortConnection.new(port_name: :a, signal: :a, direction: :in, width: 1),
            ir::PortConnection.new(port_name: :y, signal: :y, direction: :out, width: 1)
          ],
          parameters: {}
        )
      ],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )

    ir::Package.new(modules: [top, child])
  end

  def build_flat_jit_sim(nodes_or_package, top:)
    flat = RHDL::Codegen::CIRCT::Flatten.to_flat_module(nodes_or_package, top: top)
    RHDL::Sim::Native::IR::Simulator.new(
      RHDL::Sim::Native::IR.sim_json(flat, backend: :jit),
      backend: :jit
    )
  end

  it 'evaluates hierarchical package outputs correctly when flattened for JIT runtime' do
    skip 'IR JIT backend unavailable' unless RHDL::Sim::Native::IR::JIT_AVAILABLE

    sim = build_flat_jit_sim(build_hierarchical_package, top: 'top')

    sim.poke('a', 0)
    sim.evaluate
    expect(sim.peek('y')).to eq(1)
    expect(sim.peek('u__y')).to eq(1)

    sim.poke('a', 1)
    sim.evaluate
    expect(sim.peek('y')).to eq(0)
    expect(sim.peek('u__y')).to eq(0)
  end

  it 'preserves instance-result output bridges after MLIR roundtrip import when flattened for JIT runtime' do
    skip 'IR JIT backend unavailable' unless RHDL::Sim::Native::IR::JIT_AVAILABLE

    package = build_hierarchical_package
    mlir = RHDL::Codegen::CIRCT::MLIR.generate(package)
    imported = RHDL::Codegen.import_circt_mlir(mlir, strict: true, top: 'top')
    expect(imported.success?).to be(true), Array(imported.diagnostics).join("\n")

    imported_top = imported.modules.find { |mod| mod.name.to_s == 'top' }
    expect(imported_top.nets.map { |net| net.name.to_s }).to include('y_1')

    sim = build_flat_jit_sim(imported.modules, top: 'top')

    sim.poke('a', 0)
    sim.evaluate
    expect(sim.peek('y')).to eq(1)
    expect(sim.peek('u__y')).to eq(1)

    sim.poke('a', 1)
    sim.evaluate
    expect(sim.peek('y')).to eq(0)
    expect(sim.peek('u__y')).to eq(0)
  end
end
