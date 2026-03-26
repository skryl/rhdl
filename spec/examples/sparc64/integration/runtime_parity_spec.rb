# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/sparc64/utilities/integration/programs'

RSpec.describe 'SPARC64 staged-Verilog vs imported-RHDL runtime parity', slow: true do
  include Sparc64IntegrationSupport

  PARITY_BASELINE_ARTIFACT = :staged_verilog_verilator
  PARITY_CANDIDATE_ARTIFACTS = [
    {
      id: :staged_verilog_arcilator,
      label: 'staged Verilog -> circt-verilog -> Arcilator'
    },
    {
      id: :imported_ir_compiler,
      label: 'imported IR -> IR compiler'
    },
    {
      id: :rhdl_mlir_arcilator,
      label: 'RHDL -> to_mlir -> Arcilator'
    },
    {
      id: :rhdl_verilog_verilator,
      label: 'RHDL -> to_verilog -> Verilator'
    }
  ].freeze

  def expect_runner_parity!(program_name:, artifact:)
    program = RHDL::Examples::SPARC64::Integration::Programs.fetch(program_name)
    candidate = build_parity_runner(artifact: artifact)
    pending_unless_runner_contract!(candidate)

    baseline = build_parity_runner(artifact: PARITY_BASELINE_ARTIFACT)
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
    PARITY_CANDIDATE_ARTIFACTS.each do |artifact|
      it "matches exact acknowledged Wishbone traces for #{program_name} on #{artifact.fetch(:label)}", timeout: 3600 do
        pending_unless_runner_stack!
        pending_unless_runtime_backends!
        skip_unless_program_toolchain!

        expect_runner_parity!(program_name: program_name, artifact: artifact.fetch(:id))
      end
    end
  end
end
