# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'
require 'tmpdir'

RSpec.describe 'AO486 l1_icache runtime startup' do
  include AO486UnitSupport::RuntimeImportRequirements

  def build_sim
    require_reference_tree!
    require_import_tool!
    skip 'IR JIT backend unavailable' unless RHDL::Sim::Native::IR::JIT_AVAILABLE

    session = AO486UnitSupport::RuntimeImportSession.current
    record = session.module_record('l1_icache')
    source_relative_path = record.source_relative_path
    mlir = Dir.mktmpdir('ao486_l1_icache_runtime_mlir') do |dir|
      RHDL::Examples::AO486::Unit::SourceFileDriver.convert_verilog_paths_to_mlir(
        primary_path: record.staged_source_path,
        extra_paths: session.staged_dependency_verilog_files_for_source(source_relative_path),
        base_dir: dir,
        stem: 'l1_icache_runtime',
        include_dirs: session.staged_include_dirs,
        top_module: 'l1_icache'
      )
    end
    imported = RHDL::Codegen.import_circt_mlir(mlir, strict: false, top: 'l1_icache')
    expect(imported.success?).to be(true), Array(imported.diagnostics).join("\n")

    flat = RHDL::Codegen::CIRCT::Flatten.to_flat_module(imported.modules, top: 'l1_icache')
    ir_json = RHDL::Sim::Native::IR.sim_json(
      flat,
      backend: :jit
    )

    RHDL::Sim::Native::IR::Simulator.new(ir_json, backend: :jit)
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
    sim = build_sim
    prime_inputs(sim)

    step(sim, reset: true)

    first_mem_req = nil
    samples = []

    160.times do |cycle|
      step(sim, reset: false)
      samples << {
        cycle: cycle + 1,
        state: sim.peek('state'),
        update_tag_addr: sim.peek('update_tag_addr'),
        cpu_req_hold: sim.peek('CPU_REQ_hold'),
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
