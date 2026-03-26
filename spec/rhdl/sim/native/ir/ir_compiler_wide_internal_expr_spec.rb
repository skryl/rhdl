# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

RSpec.describe 'IR compiler wide internal expression lowering' do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  def build_runtime_package
    a = ir::Signal.new(name: :a, width: 64)
    c = ir::Signal.new(name: :c, width: 64)
    sel8 = ir::Signal.new(name: :sel8, width: 8)
    choose = ir::Signal.new(name: :choose, width: 1)
    we = ir::Signal.new(name: :we, width: 1)
    cab = ir::Signal.new(name: :cab, width: 1)
    cyc = ir::Signal.new(name: :cyc, width: 1)
    stb = ir::Signal.new(name: :stb, width: 1)
    bus_mux = ir::Signal.new(name: :bus_mux, width: 140)

    bus0 = ir::Concat.new(parts: [a, sel8, c, we, cab, cyc, stb], width: 140)
    bus1 = ir::Concat.new(parts: [c, sel8, a, cab, we, stb, cyc], width: 140)

    module_op = ir::ModuleOp.new(
      name: 'compiler_wide_internal_expr',
      ports: [
        ir::Port.new(name: :choose, direction: :in, width: 1),
        ir::Port.new(name: :a, direction: :in, width: 64),
        ir::Port.new(name: :sel8, direction: :in, width: 8),
        ir::Port.new(name: :c, direction: :in, width: 64),
        ir::Port.new(name: :we, direction: :in, width: 1),
        ir::Port.new(name: :cab, direction: :in, width: 1),
        ir::Port.new(name: :cyc, direction: :in, width: 1),
        ir::Port.new(name: :stb, direction: :in, width: 1),
        ir::Port.new(name: :adr, direction: :out, width: 64),
        ir::Port.new(name: :byte_sel, direction: :out, width: 8),
        ir::Port.new(name: :data_o, direction: :out, width: 64),
        ir::Port.new(name: :cyc_o, direction: :out, width: 1),
        ir::Port.new(name: :stb_o, direction: :out, width: 1)
      ],
      nets: [
        ir::Net.new(name: :bus_mux, width: 140)
      ],
      regs: [],
      assigns: [
        ir::Assign.new(
          target: :bus_mux,
          expr: ir::Mux.new(condition: choose, when_true: bus1, when_false: bus0, width: 140)
        ),
        ir::Assign.new(target: :adr, expr: ir::Slice.new(base: bus_mux, range: 139..76, width: 64)),
        ir::Assign.new(target: :byte_sel, expr: ir::Slice.new(base: bus_mux, range: 75..68, width: 8)),
        ir::Assign.new(target: :data_o, expr: ir::Slice.new(base: bus_mux, range: 67..4, width: 64)),
        ir::Assign.new(target: :cyc_o, expr: ir::Slice.new(base: bus_mux, range: 1..1, width: 1)),
        ir::Assign.new(target: :stb_o, expr: ir::Slice.new(base: bus_mux, range: 0..0, width: 1))
      ],
      processes: [],
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

  it 'preserves slices above bit 63 when they come from a wide internal packed bus' do
    sim = create_sim
    sim.reset

    sim.poke('a', 0xFEDC_BA98_7654_3210)
    sim.poke('c', 0x0123_4567_89AB_CDEF)
    sim.poke('sel8', 0xA5)
    sim.poke('we', 1)
    sim.poke('cab', 0)
    sim.poke('cyc', 1)
    sim.poke('stb', 0)

    sim.poke('choose', 0)
    sim.evaluate

    aggregate_failures 'choose=0' do
      expect(sim.peek('adr')).to eq(0xFEDC_BA98_7654_3210)
      expect(sim.peek('byte_sel')).to eq(0xA5)
      expect(sim.peek('data_o')).to eq(0x0123_4567_89AB_CDEF)
      expect(sim.peek('cyc_o')).to eq(1)
      expect(sim.peek('stb_o')).to eq(0)
    end

    sim.poke('choose', 1)
    sim.evaluate

    aggregate_failures 'choose=1' do
      expect(sim.peek('adr')).to eq(0x0123_4567_89AB_CDEF)
      expect(sim.peek('byte_sel')).to eq(0xA5)
      expect(sim.peek('data_o')).to eq(0xFEDC_BA98_7654_3210)
      expect(sim.peek('cyc_o')).to eq(0)
      expect(sim.peek('stb_o')).to eq(1)
    end
  end
end
