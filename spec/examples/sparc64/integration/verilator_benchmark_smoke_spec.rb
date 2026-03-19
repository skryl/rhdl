# frozen_string_literal: true

require 'spec_helper'
require 'benchmark'
require 'etc'
require_relative '../../../../examples/sparc64/utilities/integration/programs'

RSpec.describe 'SPARC64 staged-Verilog benchmark smoke', slow: true do
  include Sparc64IntegrationSupport

  RHDL::Examples::SPARC64::Integration::Programs.all.map(&:name).each do |program_name|
    it "runs #{program_name} to mailbox completion with no unmapped accesses", timeout: 2400 do
      pending_unless_runner_stack!
      pending_unless_runtime_backends!
      skip_unless_verilator!
      skip_unless_program_toolchain!

      program = RHDL::Examples::SPARC64::Integration::Programs.fetch(program_name)
      runner = build_headless_runner(mode: :verilog, verilator_source: :staged_verilog)
      pending_unless_runner_contract!(runner)
      pending('SPARC64 benchmark loader not implemented yet') unless runner.respond_to?(:load_benchmark)

      runner.load_benchmark(program_name)
      result = normalize_run_result(
        runner.run_until_complete(max_cycles: program.max_cycles, batch_cycles: 100_000)
      )
      trace = normalize_wishbone_trace(runner.wishbone_trace)

      expect(result[:completed]).to eq(true), "program=#{program_name}"
      expect(result[:boot_handoff_seen]).to eq(true), "program=#{program_name}"
      expect(result[:secondary_core_parked]).to eq(true), "program=#{program_name}"
      expect(runner.mailbox_status).to eq(1), "program=#{program_name}"
      expect(runner.mailbox_value).to eq(expected_benchmark_value(program_name)), "program=#{program_name}"
      expect(Array(runner.unmapped_accesses)).to eq([]), "program=#{program_name}"
      expect(trace.length).to be >= 8, "program=#{program_name}"
      expect(trace.any? { |event| event[:addr].to_i >= Sparc64IntegrationSupport::PROGRAM_BASE }).to eq(true), "program=#{program_name}"
      expect(trace.any? { |event| event[:addr].to_i == Sparc64IntegrationSupport::MAILBOX_STATUS_ADDR }).to eq(true), "program=#{program_name}"
      expect(trace.any? { |event| event[:addr].to_i == Sparc64IntegrationSupport::MAILBOX_VALUE_ADDR }).to eq(true), "program=#{program_name}"
    end
  end

  it 'benchmarks default Verilator against a --threads 4 build on prime_sieve', timeout: 2400 do
    pending_unless_runner_stack!
    pending_unless_runtime_backends!
    skip_unless_verilator!
    skip_unless_program_toolchain!
    skip 'Fewer than 4 host CPUs available' if Etc.nprocessors < 4

    program_name = :prime_sieve
    program = RHDL::Examples::SPARC64::Integration::Programs.fetch(program_name)
    single = build_headless_runner(mode: :verilog, verilator_source: :staged_verilog)
    threaded = build_headless_runner(mode: :verilog, verilator_source: :staged_verilog, threads: 4)
    pending_unless_runner_contract!(single)
    pending_unless_runner_contract!(threaded)

    single_result = nil
    threaded_result = nil

    single_time = Benchmark.measure do
      single.load_benchmark(program_name)
      single_result = normalize_run_result(
        single.run_until_complete(max_cycles: program.max_cycles, batch_cycles: 100_000)
      )
    end

    threaded_time = Benchmark.measure do
      threaded.load_benchmark(program_name)
      threaded_result = normalize_run_result(
        threaded.run_until_complete(max_cycles: program.max_cycles, batch_cycles: 100_000)
      )
    end

    expect(single_result).to include(
      completed: true,
      boot_handoff_seen: true,
      secondary_core_parked: true,
      timeout: false
    )
    expect(threaded_result).to include(
      completed: true,
      boot_handoff_seen: true,
      secondary_core_parked: true,
      timeout: false
    )
    expect(single.mailbox_status).to eq(1)
    expect(threaded.mailbox_status).to eq(1)
    expect(single.mailbox_value).to eq(expected_benchmark_value(program_name))
    expect(threaded.mailbox_value).to eq(expected_benchmark_value(program_name))
    expect(Array(single.unmapped_accesses)).to eq([])
    expect(Array(threaded.unmapped_accesses)).to eq([])

    puts format('SPARC64 prime_sieve Verilator default: %.4fs', single_time.real)
    puts format('SPARC64 prime_sieve Verilator --threads 4: %.4fs', threaded_time.real)
    puts format('SPARC64 prime_sieve ratio (threads/default): %.3fx', threaded_time.real / single_time.real)

    expect(single_time.real).to be > 0
    expect(threaded_time.real).to be > 0
  end
end
