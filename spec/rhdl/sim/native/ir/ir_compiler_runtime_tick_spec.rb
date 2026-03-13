# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

RSpec.describe 'IR compiler runtime tick lowering' do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  def build_runtime_package
    clk = ir::Signal.new(name: :clk, width: 1)
    rst_n = ir::Signal.new(name: :rst_n, width: 1)
    enable = ir::Signal.new(name: :enable, width: 1)
    state = ir::Signal.new(name: :state, width: 32)
    rst_local = ir::Signal.new(name: :rst_local, width: 1)
    fire = ir::Signal.new(name: :fire, width: 1)
    next_state = ir::Signal.new(name: :next_state, width: 32)

    module_op = ir::ModuleOp.new(
      name: 'compiler_runtime_tick',
      ports: [
        ir::Port.new(name: :clk, direction: :in, width: 1),
        ir::Port.new(name: :rst_n, direction: :in, width: 1),
        ir::Port.new(name: :enable, direction: :in, width: 1),
        ir::Port.new(name: :state_o, direction: :out, width: 32)
      ],
      nets: [
        ir::Net.new(name: :rst_local, width: 1),
        ir::Net.new(name: :fire, width: 1),
        ir::Net.new(name: :next_state, width: 32)
      ],
      regs: [
        ir::Reg.new(name: :state, width: 32, reset_value: 0)
      ],
      assigns: [
        ir::Assign.new(target: :rst_local, expr: rst_n),
        ir::Assign.new(target: :fire, expr: ir::BinaryOp.new(op: :&, left: rst_local, right: enable, width: 1)),
        ir::Assign.new(
          target: :next_state,
          expr: ir::Mux.new(
            condition: ir::BinaryOp.new(
              op: :^,
              left: rst_local,
              right: ir::Literal.new(value: 1, width: 1),
              width: 1
            ),
            when_true: ir::Literal.new(value: 0xFFF0, width: 32),
            when_false: ir::Mux.new(
              condition: fire,
              when_true: ir::BinaryOp.new(
                op: :+,
                left: state,
                right: ir::Literal.new(value: 1, width: 32),
                width: 32
              ),
              when_false: state,
              width: 32
            ),
            width: 32
          )
        ),
        ir::Assign.new(target: :state_o, expr: state)
      ],
      processes: [
        ir::Process.new(
          name: 'state_ff',
          clocked: true,
          clock: :clk,
          sensitivity_list: [],
          statements: [
            ir::SeqAssign.new(target: :state, expr: next_state)
          ]
        )
      ],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )

    ir::Package.new(modules: [module_op])
  end

  def create_sim
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    runtime_json = RHDL::Sim::Native::IR.sim_json(build_runtime_package, backend: :compiler)
    RHDL::Sim::Native::IR::Simulator.new(runtime_json, backend: :compiler)
  end

  it 'keeps nested sequential next-state expressions correct on the compiler backend' do
    sim = create_sim
    sim.reset

    sim.poke('enable', 0)
    sim.poke('clk', 0)
    sim.poke('rst_n', 0)
    sim.evaluate
    sim.poke('clk', 1)
    sim.tick

    expect(sim.peek('state_o')).to eq(0xFFF0)

    sim.poke('clk', 0)
    sim.poke('rst_n', 1)
    sim.poke('enable', 0)
    sim.evaluate
    sim.poke('clk', 1)
    sim.tick

    expect(sim.peek('state_o')).to eq(0xFFF0)

    sim.poke('clk', 0)
    sim.poke('rst_n', 1)
    sim.poke('enable', 1)
    sim.evaluate
    sim.poke('clk', 1)
    sim.tick

    expect(sim.peek('state_o')).to eq(0xFFF1)
  end
end
