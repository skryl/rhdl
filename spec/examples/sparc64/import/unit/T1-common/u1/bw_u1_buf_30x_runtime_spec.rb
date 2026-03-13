# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

require_relative '../../../../../../../examples/sparc64/import/T1-common/u1/bw_u1_buf_30x'

RSpec.describe BwU1Buf30x do
  def create_sim
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    ir_json = RHDL::Sim::Native::IR.sim_json(
      described_class.to_flat_circt_nodes(top_name: 'bw_u1_buf_30x'),
      backend: :compiler
    )
    RHDL::Sim::Native::IR::Simulator.new(ir_json, backend: :compiler)
  end

  it 'drives z from a on the compiler backend' do
    sim = create_sim
    sim.reset

    sim.poke('a', 0)
    sim.evaluate
    expect(sim.peek('z')).to eq(0)

    sim.poke('a', 1)
    sim.evaluate
    expect(sim.peek('z')).to eq(1)
  end
end
