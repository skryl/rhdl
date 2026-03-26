# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

require_relative '../../../../examples/gameboy/utilities/tasks/run_task'
require_relative './headless_runtime_support'

RSpec.describe 'GameBoy imported design behavioral parity on standard Verilator runners', slow: true do
  include GameboyImportHeadlessRuntimeSupport

  TRACE_CYCLES = Integer(ENV.fetch('RHDL_GAMEBOY_IMPORT_BEHAVIOR_TRACE_CYCLES', '8192'))
  TRACE_SAMPLE_EVERY = Integer(ENV.fetch('RHDL_GAMEBOY_IMPORT_BEHAVIOR_TRACE_SAMPLE_EVERY', '64'))
  TRACE_COMPARE_LIMIT = Integer(ENV.fetch('RHDL_GAMEBOY_IMPORT_BEHAVIOR_TRACE_COMPARE_LIMIT', '64'))
  PARITY_LEGS = %i[staged normalized raised].freeze

  it 'matches staged source, normalized import, and raised RHDL on the shared headless Verilator harness', timeout: 1800 do
    require_reference_tree!
    require_tool!('ghdl')
    require_tool!('circt-verilog')
    require_tool!('verilator')
    require_boot_rom!

    out_dir, workspace = stable_import_dirs('gameboy_import_behavior')
    rom_bytes = RHDL::Examples::GameBoy::Tasks::RunTask.create_demo_rom
    import_gameboy!(out_dir: out_dir, workspace: workspace, emit_runtime_json: false)

    results = {}
    PARITY_LEGS.each do |leg|
      with_headless_runner(leg: leg, out_dir: out_dir) do |headless|
        results[leg] = collect_runtime_capture(
          headless,
          rom_bytes: rom_bytes,
          trace_cycles: TRACE_CYCLES,
          trace_sample_every: TRACE_SAMPLE_EVERY,
          total_cycles: TRACE_CYCLES
        )
      end
      trim_ruby_heap!
    end

    failures = []
    summary_lines = []

    PARITY_LEGS.combination(2) do |lhs, rhs|
      lhs_result = results.fetch(lhs)
      rhs_result = results.fetch(rhs)
      record_trace_comparison!(
        summary_lines: summary_lines,
        failures: failures,
        lhs_name: lhs.to_s,
        lhs_trace: lhs_result.fetch(:trace),
        rhs_name: rhs.to_s,
        rhs_trace: rhs_result.fetch(:trace),
        limit: TRACE_COMPARE_LIMIT
      )
      record_video_comparison!(
        summary_lines: summary_lines,
        failures: failures,
        lhs_name: lhs.to_s,
        lhs_video: lhs_result.fetch(:video),
        rhs_name: rhs.to_s,
        rhs_video: rhs_result.fetch(:video)
      )
    end

    if failures.any?
      raise RSpec::Expectations::ExpectationNotMetError,
            "Behavior parity summary:\n" \
            "#{summary_lines.map { |line| "  - #{line}" }.join("\n")}\n" \
            "Failures:\n" \
            "#{failures.map { |line| "  - #{line}" }.join("\n")}"
    end
  end
end
