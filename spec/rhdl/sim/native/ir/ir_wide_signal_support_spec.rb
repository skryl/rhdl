# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

module RHDL
  module SpecFixtures
    class IrWideSignalProbe < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :clk
      input :rst
      input :load
      input :seed, width: 128

      output :joined, width: 128
      output :window, width: 64
      output :plus_one, width: 128
      output :q, width: 128

      behavior do
        joined <= seed
        window <= seed[95..32]
        plus_one <= seed + lit(1, width: 128)
      end

      sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        q <= mux(load, seed + lit(1, width: 128), q)
      end
    end
  end
end

RSpec.describe 'IR native runtime wide signal support' do
  WIDE_SEED = (0x0123_4567_89AB_CDEF << 64) | 0xFEDC_BA98_7654_3210
  WIDE_WINDOW = 0x89AB_CDEF_FEDC_BA98
  MAX_U128 = (1 << 128) - 1
  LOW64_CARRY_SEED = (1 << 64) - 1
  LOW64_CARRY_RESULT = 1 << 64

  def wide_ir
    RHDL::SpecFixtures::IrWideSignalProbe.to_flat_circt_nodes(top_name: 'ir_wide_signal_probe')
  end

  def create_sim(backend)
    ir_json = RHDL::Sim::Native::IR.sim_json(wide_ir, backend: backend)
    RHDL::Sim::Native::IR::Simulator.new(ir_json, backend: backend)
  end

  def low_phase(sim, seed:, load: 0, rst: 0)
    sim.poke('rst', rst)
    sim.poke('load', load)
    sim.poke('seed', seed)
    sim.poke('clk', 0)
    sim.evaluate
  end

  def step(sim, seed:, load:, rst: 0)
    low_phase(sim, seed: seed, load: load, rst: rst)
    sim.poke('rst', rst)
    sim.poke('load', load)
    sim.poke('seed', seed)
    sim.poke('clk', 1)
    sim.tick
  end

  [
    [:interpreter, -> { RHDL::Sim::Native::IR::INTERPRETER_AVAILABLE }],
    [:jit, -> { RHDL::Sim::Native::IR::JIT_AVAILABLE }]
  ].each do |backend, available|
    describe backend do
      before do
        skip "#{backend} backend not available" unless instance_exec(&available)
      end

      it 'supports 128-bit poke/peek and cross-boundary combinational expressions' do
        sim = create_sim(backend)
        sim.reset

        low_phase(sim, seed: WIDE_SEED)

        expect(sim.peek('joined')).to eq(WIDE_SEED)
        expect(sim.peek('window')).to eq(WIDE_WINDOW)
        expect(sim.peek('plus_one')).to eq((WIDE_SEED + 1) & MAX_U128)
      end

      it 'supports 128-bit indexed signal access and carries across bit 63 on tick' do
        sim = create_sim(backend)
        sim.reset

        seed_idx = sim.get_signal_idx('seed')
        q_idx = sim.get_signal_idx('q')

        sim.poke_by_idx(seed_idx, LOW64_CARRY_SEED)
        sim.poke('rst', 0)
        sim.poke('load', 1)
        sim.poke('clk', 0)
        sim.evaluate

        expect(sim.peek_by_idx(seed_idx)).to eq(LOW64_CARRY_SEED)

        sim.poke_by_idx(seed_idx, LOW64_CARRY_SEED)
        sim.poke('rst', 0)
        sim.poke('load', 1)
        sim.poke('clk', 1)
        sim.tick

        expect(sim.peek_by_idx(q_idx)).to eq(LOW64_CARRY_RESULT)
        expect(sim.peek('q')).to eq(LOW64_CARRY_RESULT)
      end

      it 'masks 128-bit arithmetic to the declared width' do
        sim = create_sim(backend)
        sim.reset

        low_phase(sim, seed: MAX_U128)

        expect(sim.peek('plus_one')).to eq(0)
      end
    end
  end
end
