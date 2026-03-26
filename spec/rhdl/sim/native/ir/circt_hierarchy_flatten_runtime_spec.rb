# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CIRCT hierarchical runtime flattening' do
  class HierarchicalSequentialChild < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior
    include RHDL::DSL::Sequential

    input :clk
    input :rst
    input :din
    output :y, width: 30
    wire :y_reg, width: 30

    sequential clock: :clk, reset: :rst, reset_values: { y_reg: 0 } do
      y_reg <= mux(din, lit(64, width: 30), lit(0, width: 30))
    end

    behavior do
      y <= y_reg
    end
  end

  class HierarchicalSequentialTop < RHDL::HDL::SequentialComponent
    include RHDL::DSL::Behavior

    input :clk
    input :rst
    input :din
    output :y, width: 30
    wire :child_y, width: 30

    instance :u, HierarchicalSequentialChild

    port :clk => [:u, :clk]
    port :rst => [:u, :rst]
    port :din => [:u, :din]
    port [:u, :y] => :child_y

    behavior do
      y <= child_y
    end
  end

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

  {
    interpret: [:INTERPRETER_AVAILABLE, 'IR interpreter'],
    jit: [:JIT_AVAILABLE, 'IR JIT'],
    compile: [:COMPILER_AVAILABLE, 'IR compiler']
  }.each do |backend, (availability_const, label)|
    it "does not duplicate hierarchical sequential output bridges for #{label}" do
      skip "#{label} unavailable" unless RHDL::Sim::Native::IR.const_get(availability_const)

      flat = HierarchicalSequentialTop.to_flat_circt_nodes(top_name: "hierarchical_seq_top_#{backend}")
      bridge_targets = flat.assigns.map { |assign| assign.target.to_s }

      expect(bridge_targets.count('child_y')).to eq(1)
      expect(bridge_targets.count('u__y')).to eq(1)

      sim = RHDL::Sim::Native::IR::Simulator.new(
        RHDL::Sim::Native::IR.sim_json(flat, backend: backend),
        backend: backend
      )

      sim.reset
      sim.poke('rst', 0)
      sim.poke('din', 1)
      sim.poke('clk', 0)
      sim.evaluate
      sim.poke('clk', 1)
      sim.tick
      sim.poke('clk', 0)
      sim.evaluate

      expect(sim.peek('u__y')).to eq(64)
      expect(sim.peek('child_y')).to eq(64)
      expect(sim.peek('y')).to eq(64)
    end
  end

  it 'materializes backing state for imported sequential output targets on the legacy flat runtime path' do
    skip 'IR JIT unavailable' unless RHDL::Sim::Native::IR::JIT_AVAILABLE

    mlir = <<~MLIR
      hw.module @regwrap(%d: i8, %clk: i1) -> (q: i8) {
        %clock = seq.to_clock %clk
        %q = seq.compreg %d, %clock : i8
        hw.output %q : i8
      }
    MLIR

    raised = RHDL::Codegen.raise_circt_components(mlir, top: 'regwrap', strict: false)
    expect(raised.success?).to be(true), Array(raised.diagnostics).join("\n")

    flat = raised.components.fetch('regwrap').to_flat_circt_nodes(top_name: 'regwrap')
    sim = RHDL::Sim::Native::IR::Simulator.new(
      RHDL::Sim::Native::IR.sim_json(flat, backend: :jit),
      backend: :jit
    )

    sim.poke('d', 7)
    sim.poke('clk', 0)
    sim.evaluate
    expect(sim.peek('q')).to eq(0)

    sim.poke('clk', 1)
    sim.tick
    expect(sim.peek('q')).to eq(7)
  end
end
