# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

require_relative '../../../../../../../examples/sparc64/import/T1-common/u1/bw_u1_aoi21_4x'
require_relative '../../../../../../../examples/sparc64/import/T1-common/u1/bw_u1_aoi22_2x'
require_relative '../../../../../../../examples/sparc64/import/T1-common/u1/bw_u1_buf_10x'
require_relative '../../../../../../../examples/sparc64/import/T1-common/u1/bw_u1_inv_10x'
require_relative '../../../../../../../examples/sparc64/import/T1-common/u1/bw_u1_minbuf_5x'
require_relative '../../../../../../../examples/sparc64/import/T1-common/u1/bw_u1_muxi21_2x'
require_relative '../../../../../../../examples/sparc64/import/T1-common/u1/bw_u1_nand2_10x'
require_relative '../../../../../../../examples/sparc64/import/T1-common/u1/bw_u1_nand3_4x'
require_relative '../../../../../../../examples/sparc64/import/T1-common/u1/bw_u1_nor3_8x'
require_relative '../../../../../../../examples/sparc64/import/T1-common/u1/bw_u1_soffm2_4x'

RSpec.describe 'SPARC64 U1 runtime primitives' do
  def build_sim(component_class)
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    ir_json = RHDL::Sim::Native::IR.sim_json(
      component_class.to_flat_circt_nodes(top_name: component_class.verilog_module_name),
      backend: :compiler
    )
    RHDL::Sim::Native::IR::Simulator.new(ir_json, backend: :compiler)
  end

  it 'implements the combinational gate shims on the compiler backend' do
    inv = build_sim(BwU1Inv10x)
    inv.reset
    inv.poke('a', 0)
    inv.evaluate
    expect(inv.peek('z')).to eq(1)
    inv.poke('a', 1)
    inv.evaluate
    expect(inv.peek('z')).to eq(0)

    buf = build_sim(BwU1Buf10x)
    buf.reset
    buf.poke('a', 1)
    buf.evaluate
    expect(buf.peek('z')).to eq(1)

    minbuf = build_sim(BwU1Minbuf5x)
    minbuf.reset
    minbuf.poke('a', 0)
    minbuf.evaluate
    expect(minbuf.peek('z')).to eq(0)
    minbuf.poke('a', 1)
    minbuf.evaluate
    expect(minbuf.peek('z')).to eq(1)

    nand2 = build_sim(BwU1Nand210x)
    nand2.reset
    nand2.poke('a', 1)
    nand2.poke('b', 1)
    nand2.evaluate
    expect(nand2.peek('z')).to eq(0)
    nand2.poke('b', 0)
    nand2.evaluate
    expect(nand2.peek('z')).to eq(1)

    nand3 = build_sim(BwU1Nand34x)
    nand3.reset
    nand3.poke('a', 1)
    nand3.poke('b', 1)
    nand3.poke('c', 1)
    nand3.evaluate
    expect(nand3.peek('z')).to eq(0)
    nand3.poke('c', 0)
    nand3.evaluate
    expect(nand3.peek('z')).to eq(1)

    nor3 = build_sim(BwU1Nor38x)
    nor3.reset
    nor3.poke('a', 0)
    nor3.poke('b', 0)
    nor3.poke('c', 0)
    nor3.evaluate
    expect(nor3.peek('z')).to eq(1)
    nor3.poke('b', 1)
    nor3.evaluate
    expect(nor3.peek('z')).to eq(0)

    aoi21 = build_sim(BwU1Aoi214x)
    aoi21.reset
    aoi21.poke('a', 0)
    aoi21.poke('b1', 0)
    aoi21.poke('b2', 1)
    aoi21.evaluate
    expect(aoi21.peek('z')).to eq(1)
    aoi21.poke('b1', 1)
    aoi21.evaluate
    expect(aoi21.peek('z')).to eq(0)

    aoi22 = build_sim(BwU1Aoi222x)
    aoi22.reset
    aoi22.poke('a1', 0)
    aoi22.poke('a2', 1)
    aoi22.poke('b1', 0)
    aoi22.poke('b2', 1)
    aoi22.evaluate
    expect(aoi22.peek('z')).to eq(1)
    aoi22.poke('a1', 1)
    aoi22.poke('a2', 1)
    aoi22.evaluate
    expect(aoi22.peek('z')).to eq(0)

    muxi = build_sim(BwU1Muxi212x)
    muxi.reset
    muxi.poke('s', 0)
    muxi.poke('d0', 0)
    muxi.poke('d1', 1)
    muxi.evaluate
    expect(muxi.peek('z')).to eq(1)
    muxi.poke('s', 1)
    muxi.evaluate
    expect(muxi.peek('z')).to eq(0)
  end

  it 'implements the scanable mux flop shim on the compiler backend' do
    sim = build_sim(BwU1Soffm24x)
    sim.reset

    sim.poke('ck', 0)
    sim.evaluate

    sim.poke('se', 0)
    sim.poke('sd', 0)
    sim.poke('s', 0)
    sim.poke('d0', 1)
    sim.poke('d1', 0)
    sim.poke('ck', 1)
    sim.tick
    expect(sim.peek('q')).to eq(1)
    expect(sim.peek('so')).to eq(1)

    sim.poke('ck', 0)
    sim.evaluate
    sim.poke('s', 1)
    sim.poke('d0', 0)
    sim.poke('d1', 0)
    sim.poke('ck', 1)
    sim.tick
    expect(sim.peek('q')).to eq(0)
    expect(sim.peek('so')).to eq(0)

    sim.poke('ck', 0)
    sim.evaluate
    sim.poke('se', 1)
    sim.poke('sd', 1)
    sim.poke('ck', 1)
    sim.tick
    expect(sim.peek('q')).to eq(1)
    expect(sim.peek('so')).to eq(1)
  end
end
