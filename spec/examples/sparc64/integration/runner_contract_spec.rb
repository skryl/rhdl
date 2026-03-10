# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SPARC64 integration runner contract' do
  include Sparc64IntegrationSupport

  it 'defines the benchmark and memory ABI constants for the integration suite' do
    expect(sparc64_benchmark_names).to eq(%i[prime_sieve mandelbrot game_of_life])
    expect(Sparc64IntegrationSupport::MAILBOX_STATUS_ADDR).to eq(0x0000_1000)
    expect(Sparc64IntegrationSupport::MAILBOX_VALUE_ADDR).to eq(0x0000_1008)
    expect(Sparc64IntegrationSupport::PROGRAM_BASE).to eq(0x0000_4000)
    expect(Sparc64IntegrationSupport::STACK_TOP).to eq(0x0002_0000)
  end

  it 'defines HeadlessRunner once the SPARC64 runner stack exists' do
    pending_unless_runner_stack!
    expect(sparc64_headless_runner_class).to eq(RHDL::Examples::SPARC64::HeadlessRunner)
  end

  it 'defines both concrete runtime backends once the SPARC64 runner stack exists' do
    pending_unless_runner_stack!
    pending_unless_runtime_backends!

    expect(sparc64_ir_runner_class).to eq(RHDL::Examples::SPARC64::IrRunner)
    expect(sparc64_verilator_runner_class).not_to be_nil
  end

  it 'requires the headless integration contract methods once the runner exists' do
    runner = build_headless_runner(mode: :ir, sim: :compile)
    pending_unless_runner_contract!(runner)

    missing = Sparc64IntegrationSupport::REQUIRED_HEADLESS_METHODS.reject { |method| runner.respond_to?(method) }
    expect(missing).to eq([])
  end

  it 'requires run_until_complete to return the startup/parity bookkeeping keys' do
    runner = build_headless_runner(mode: :ir, sim: :compile)
    pending_unless_runner_contract!(runner)
    pending('SPARC64 benchmark loader not implemented yet') unless runner.respond_to?(:load_benchmark)

    runner.load_benchmark(:prime_sieve)
    result = normalize_run_result(runner.run_until_complete(max_cycles: 1_000))

    missing = Sparc64IntegrationSupport::REQUIRED_RUN_RESULT_KEYS.reject { |key| result.key?(key) }
    expect(missing).to eq([])
  end

  it 'requires acknowledged Wishbone events to expose the full parity shape' do
    runner = build_headless_runner(mode: :ir, sim: :compile)
    pending_unless_runner_contract!(runner)
    pending('SPARC64 benchmark loader not implemented yet') unless runner.respond_to?(:load_benchmark)

    runner.load_benchmark(:prime_sieve)
    runner.run_until_complete(max_cycles: 1_000)
    trace = normalize_wishbone_trace(runner.wishbone_trace)
    pending('SPARC64 wishbone trace not populated yet') if trace.empty?

    missing = Sparc64IntegrationSupport::REQUIRED_EVENT_KEYS.reject { |key| trace.first.key?(key) }
    expect(missing).to eq([])
  end
end
