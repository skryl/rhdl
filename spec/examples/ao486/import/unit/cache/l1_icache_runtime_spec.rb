# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

RSpec.describe 'AO486 l1_icache runtime startup' do
  include AO486UnitSupport::RuntimeImportRequirements

  def build_sim(input_format: :circt)
    require_reference_tree!
    require_import_tool!
    skip 'IR JIT backend unavailable' unless RHDL::Sim::Native::IR::JIT_AVAILABLE

    session = AO486UnitSupport::RuntimeImportSession.current
    record = session.module_record('l1_icache')
    case input_format
    when :circt
      flat = record.component_class.to_flat_circt_nodes(top_name: 'l1_icache')
      ir_json = RHDL::Sim::Native::IR.sim_json(
        flat,
        backend: :jit
      )

      RHDL::Sim::Native::IR::Simulator.new(ir_json, backend: :jit)
    when :mlir
      mlir = record.component_class.to_mlir_hierarchy(top_name: 'l1_icache')
      RHDL::Sim::Native::IR::Simulator.new(mlir, backend: :jit, input_format: :mlir)
    else
      raise ArgumentError, "unsupported input format #{input_format.inspect}"
    end
  end

  def prime_inputs(sim)
    {
      'DISABLE' => 1,
      'pr_reset' => 0,
      'CPU_REQ' => 1,
      'CPU_ADDR' => 0xFFFF0,
      'MEM_DONE' => 0,
      'MEM_DATA' => 0,
      'snoop_addr' => 0,
      'snoop_data' => 0,
      'snoop_be' => 0,
      'snoop_we' => 0
    }.each { |name, value| sim.poke(name, value) }
  end

  def step(sim, reset:)
    sim.poke('CLK', 0)
    sim.poke('RESET', reset ? 1 : 0)
    sim.evaluate
    sim.poke('CLK', 1)
    sim.poke('RESET', reset ? 1 : 0)
    sim.tick
  end

  it 'delays the first memory request until the startup tag clear sweep completes on IR JIT', timeout: 480 do
    sim = build_sim(input_format: :circt)
    prime_inputs(sim)

    step(sim, reset: true)

    first_mem_req = nil
    samples = []

    160.times do |cycle|
      step(sim, reset: false)
      samples << {
        cycle: cycle + 1,
        state: sim.peek('rt_tmp_4_3'),
        update_tag_addr: sim.peek('rt_tmp_5_7'),
        cpu_req_hold: sim.peek('rt_tmp_9_1'),
        mem_req: sim.peek('MEM_REQ'),
        mem_addr: sim.peek('MEM_ADDR')
      }

      next unless sim.peek('MEM_REQ') == 1

      first_mem_req = [cycle + 1, sim.peek('MEM_ADDR')]
      break
    end

    failure_context = [
      "first samples=#{samples.first(4).inspect}",
      "last samples=#{samples.last(4).inspect}"
    ].join("\n")

    expect(first_mem_req).not_to be_nil, failure_context
    expect(first_mem_req.fetch(0)).to be > 100
    expect(first_mem_req.fetch(0)).to be < 160
    expect(first_mem_req.fetch(1)).to eq(0xFFFE0)
  end

  it 'delays the first memory request until the startup tag clear sweep completes on IR JIT via the MLIR frontend', timeout: 480 do
    sim = build_sim(input_format: :mlir)
    prime_inputs(sim)

    step(sim, reset: true)

    first_mem_req = nil
    samples = []

    160.times do |cycle|
      step(sim, reset: false)
      samples << {
        cycle: cycle + 1,
        state: sim.peek('rt_tmp_4_3'),
        update_tag_addr: sim.peek('rt_tmp_5_7'),
        cpu_req_hold: sim.peek('rt_tmp_9_1'),
        mem_req: sim.peek('MEM_REQ'),
        mem_addr: sim.peek('MEM_ADDR')
      }

      next unless sim.peek('MEM_REQ') == 1

      first_mem_req = [cycle + 1, sim.peek('MEM_ADDR')]
      break
    end

    failure_context = [
      "first samples=#{samples.first(4).inspect}",
      "last samples=#{samples.last(4).inspect}"
    ].join("\n")

    expect(first_mem_req).not_to be_nil, failure_context
    expect(first_mem_req.fetch(0)).to be > 100
    expect(first_mem_req.fetch(0)).to be < 160
    expect(first_mem_req.fetch(1)).to eq(0xFFFE0)
  end
end
