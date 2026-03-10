# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SPARC64 staged-Verilog vs imported-RHDL runtime parity', slow: true do
  include Sparc64IntegrationSupport

  it 'matches exact acknowledged Wishbone traces on the named benchmarks', timeout: 900 do
    pending_unless_runner_stack!
    pending_unless_runtime_backends!
    skip_unless_ir_compiler!
    skip_unless_verilator!
    skip_unless_program_toolchain!

    ir_runner = build_headless_runner(mode: :ir, sim: :compile)
    vl_runner = build_headless_runner(mode: :verilog)
    pending_unless_runner_contract!(ir_runner)
    pending_unless_runner_contract!(vl_runner)

    sparc64_benchmark_names.each do |program_name|
      pending('SPARC64 benchmark loader not implemented yet') unless ir_runner.respond_to?(:load_benchmark) && vl_runner.respond_to?(:load_benchmark)

      ir_runner.load_benchmark(program_name)
      ir_result = normalize_run_result(ir_runner.run_until_complete(max_cycles: 4_000_000))
      ir_trace = normalize_wishbone_trace(ir_runner.wishbone_trace)

      vl_runner.load_benchmark(program_name)
      vl_result = normalize_run_result(vl_runner.run_until_complete(max_cycles: 4_000_000))
      vl_trace = normalize_wishbone_trace(vl_runner.wishbone_trace)

      expect(ir_result[:completed]).to eq(true), "program=#{program_name}"
      expect(vl_result[:completed]).to eq(true), "program=#{program_name}"
      expect(ir_result[:boot_handoff_seen]).to eq(true), "program=#{program_name}"
      expect(vl_result[:boot_handoff_seen]).to eq(true), "program=#{program_name}"
      expect(ir_result[:secondary_core_parked]).to eq(true), "program=#{program_name}"
      expect(vl_result[:secondary_core_parked]).to eq(true), "program=#{program_name}"
      expect(vl_trace).to eq(ir_trace), "program=#{program_name}"
    end
  end
end
