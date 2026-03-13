# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

require_relative '../../../../../../../examples/sparc64/import/T1-common/common/cluster_header'

RSpec.describe ClusterHeader do
  def create_sim
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE

    ir_json = RHDL::Sim::Native::IR.sim_json(
      described_class.to_flat_circt_nodes(top_name: 'cluster_header'),
      backend: :compiler
    )
    RHDL::Sim::Native::IR::Simulator.new(ir_json, backend: :compiler)
  end

  it 'propagates reset/debug repeaters across the native runner low/high clock phases' do
    sim = create_sim
    sim.reset

    {
      'cluster_cken' => 1,
      'arst_l' => 1,
      'adbginit_l' => 1,
      'se' => 0,
      'si' => 0
    }.each { |name, value| sim.poke(name, value) }

    sim.poke('gclk', 0)
    sim.poke('grst_l', 0)
    sim.poke('gdbginit_l', 0)
    sim.evaluate

    expect(sim.peek('rclk')).to eq(0)
    expect(sim.peek('cluster_grst_l')).to eq(0)
    expect(sim.peek('dbginit_l')).to eq(0)
    expect(sim.peek('so')).to eq(0)

    sim.poke('gclk', 0)
    sim.poke('grst_l', 1)
    sim.poke('gdbginit_l', 1)
    sim.evaluate

    expect(sim.peek('cluster_grst_l')).to eq(1)
    expect(sim.peek('dbginit_l')).to eq(1)
    expect(sim.peek('rclk')).to eq(0)

    sim.poke('gclk', 1)
    sim.poke('grst_l', 1)
    sim.poke('gdbginit_l', 1)
    sim.tick

    expect(sim.peek('cluster_grst_l')).to eq(1)
    expect(sim.peek('dbginit_l')).to eq(1)
    expect(sim.peek('rclk')).to eq(1)
  end
end
