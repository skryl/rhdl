# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/sparc64/utilities/integration/programs'

RSpec.describe 'SPARC64 staged-Verilog benchmark smoke', slow: true do
  include Sparc64IntegrationSupport

  it 'runs prime_sieve to mailbox completion with no unmapped accesses', timeout: 2400 do
    pending_unless_runner_stack!
    pending_unless_runtime_backends!
    skip_unless_verilator!
    skip_unless_program_toolchain!

    program = RHDL::Examples::SPARC64::Integration::Programs.fetch(:prime_sieve)
    runner = build_headless_runner(mode: :verilog)
    pending_unless_runner_contract!(runner)
    pending('SPARC64 benchmark loader not implemented yet') unless runner.respond_to?(:load_benchmark)

    runner.load_benchmark(:prime_sieve)
    result = normalize_run_result(
      runner.run_until_complete(max_cycles: program.max_cycles, batch_cycles: 100_000)
    )
    trace = normalize_wishbone_trace(runner.wishbone_trace)

    expect(result[:completed]).to eq(true)
    expect(result[:boot_handoff_seen]).to eq(true)
    expect(result[:secondary_core_parked]).to eq(true)
    expect(runner.mailbox_status).to eq(1)
    expect(runner.mailbox_value).to eq(expected_benchmark_value(:prime_sieve))
    expect(Array(runner.unmapped_accesses)).to eq([])
    expect(trace.length).to be >= 8
    expect(trace.any? { |event| event[:addr].to_i >= Sparc64IntegrationSupport::PROGRAM_BASE }).to eq(true)
    expect(trace.any? { |event| event[:addr].to_i == Sparc64IntegrationSupport::MAILBOX_STATUS_ADDR }).to eq(true)
    expect(trace.any? { |event| event[:addr].to_i == Sparc64IntegrationSupport::MAILBOX_VALUE_ADDR }).to eq(true)
  end
end
