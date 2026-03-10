# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SPARC64 runtime benchmark correctness', slow: true do
  include Sparc64IntegrationSupport

  it 'reaches the expected mailbox values with no unmapped accesses on all named benchmarks', timeout: 900 do
    pending_unless_runner_stack!
    skip_unless_ir_compiler!
    skip_unless_program_toolchain!

    runner = build_headless_runner(mode: :ir, sim: :compile)
    pending_unless_runner_contract!(runner)

    sparc64_benchmark_names.each do |program_name|
      pending('SPARC64 benchmark loader not implemented yet') unless runner.respond_to?(:load_benchmark)

      runner.load_benchmark(program_name)
      result = normalize_run_result(runner.run_until_complete(max_cycles: 4_000_000))
      trace = normalize_wishbone_trace(runner.wishbone_trace)

      expect(result[:completed]).to eq(true), "program=#{program_name}"
      expect(result[:boot_handoff_seen]).to eq(true), "program=#{program_name}"
      expect(result[:secondary_core_parked]).to eq(true), "program=#{program_name}"
      expect(runner.mailbox_status).to eq(1), "program=#{program_name}"
      expect(runner.mailbox_value).to eq(expected_benchmark_value(program_name)), "program=#{program_name}"
      expect(Array(runner.unmapped_accesses)).to eq([]), "program=#{program_name}"
      expect(trace.length).to be >= 8, "program=#{program_name}"
      expect(trace.any? { |event| event[:addr].to_i == Sparc64IntegrationSupport::MAILBOX_STATUS_ADDR }).to eq(true), "program=#{program_name}"
      expect(trace.any? { |event| event[:addr].to_i == Sparc64IntegrationSupport::MAILBOX_VALUE_ADDR }).to eq(true), "program=#{program_name}"
    end
  end
end
