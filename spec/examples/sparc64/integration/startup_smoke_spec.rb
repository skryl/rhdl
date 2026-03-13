# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SPARC64 integration startup smoke', slow: true do
  include Sparc64IntegrationSupport

  it 'boots through the flash shim, hands off to DRAM, parks core 1, and reaches mailbox completion', timeout: 3600 do
    pending_unless_runner_stack!
    pending_unless_runtime_backends!
    skip_unless_ir_compiler!
    skip_unless_program_toolchain!

    runner = build_headless_runner(mode: :ir, sim: :compile, compile_mode: :rustc)
    pending_unless_runner_contract!(runner)
    pending('SPARC64 benchmark loader not implemented yet') unless runner.respond_to?(:load_benchmark)

    runner.load_benchmark(:prime_sieve)
    result = normalize_run_result(runner.run_until_complete(max_cycles: 2_000_000, batch_cycles: 100_000))

    expect(result[:completed]).to eq(true)
    expect(result[:boot_handoff_seen]).to eq(true)
    expect(result[:secondary_core_parked]).to eq(true)
    expect(runner.mailbox_status).to eq(1)
    expect(runner.mailbox_value).to eq(expected_benchmark_value(:prime_sieve))
    expect(Array(runner.unmapped_accesses)).to eq([])

    trace = normalize_wishbone_trace(runner.wishbone_trace)
    expect(trace).not_to be_empty
    expect(trace.any? { |event| event[:addr].to_i >= Sparc64IntegrationSupport::PROGRAM_BASE }).to eq(true)
  end
end
