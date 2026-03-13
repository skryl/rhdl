# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/sparc64/utilities/integration/programs'

RSpec.describe 'SPARC64 staged-Verilog vs imported-RHDL runtime parity', slow: true do
  include Sparc64IntegrationSupport

  def expect_runner_parity!(program_name:, runner_mode:, runner_sim: nil, compile_mode: :rustc)
    program = RHDL::Examples::SPARC64::Integration::Programs.fetch(program_name)
    candidate = build_headless_runner(mode: runner_mode, sim: runner_sim, compile_mode: compile_mode)
    pending_unless_runner_contract!(candidate)

    baseline = build_headless_runner(mode: :verilog)
    pending_unless_runner_contract!(baseline)

    candidate.load_benchmark(program_name)
    candidate_result = normalize_run_result(
      candidate.run_until_complete(max_cycles: program.max_cycles, batch_cycles: 100_000)
    )
    candidate_trace = normalize_wishbone_trace(candidate.wishbone_trace)

    baseline.load_benchmark(program_name)
    baseline_result = normalize_run_result(
      baseline.run_until_complete(max_cycles: program.max_cycles, batch_cycles: 100_000)
    )
    baseline_trace = normalize_wishbone_trace(baseline.wishbone_trace)

    expect(candidate_result[:completed]).to eq(true), "program=#{program_name}"
    expect(baseline_result[:completed]).to eq(true), "program=#{program_name}"
    expect(candidate_result[:boot_handoff_seen]).to eq(true), "program=#{program_name}"
    expect(baseline_result[:boot_handoff_seen]).to eq(true), "program=#{program_name}"
    expect(candidate_result[:secondary_core_parked]).to eq(true), "program=#{program_name}"
    expect(baseline_result[:secondary_core_parked]).to eq(true), "program=#{program_name}"
    expect(baseline_trace).to eq(candidate_trace), "program=#{program_name}"
  end

  RHDL::Examples::SPARC64::Integration::Programs.all.map(&:name).each do |program_name|
    it "matches exact acknowledged Wishbone traces for #{program_name} on IR compile", timeout: 3600 do
      pending_unless_runner_stack!
      pending_unless_runtime_backends!
      skip_unless_ir_compiler!
      skip_unless_verilator!
      skip_unless_program_toolchain!

      expect_runner_parity!(program_name: program_name, runner_mode: :ir, runner_sim: :compile, compile_mode: :rustc)
    end

    it "matches exact acknowledged Wishbone traces for #{program_name} on ARC compile", timeout: 3600 do
      pending_unless_runner_stack!
      pending_unless_runtime_backends!
      pending_unless_arcilator_backends!
      skip_unless_verilator!
      skip_unless_arcilator!
      skip_unless_program_toolchain!

      expect_runner_parity!(program_name: program_name, runner_mode: :arcilator, runner_sim: :compile)
    end

    it "matches exact acknowledged Wishbone traces for #{program_name} on ARC jit", timeout: 3600 do
      pending_unless_runner_stack!
      pending_unless_runtime_backends!
      pending_unless_arcilator_backends!
      skip_unless_verilator!
      skip_unless_arcilator_jit!
      skip_unless_program_toolchain!

      expect_runner_parity!(program_name: program_name, runner_mode: :arcilator, runner_sim: :jit)
    end
  end
end
