# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

require_relative './headless_runtime_support'

RSpec.describe 'GameBoy mixed import runtime parity (HeadlessRunner/VerilatorRunner/VerilatorRunner/VerilatorRunner)', slow: true do
  include GameboyImportHeadlessRuntimeSupport

  MAX_CYCLES = Integer(ENV.fetch('RHDL_GAMEBOY_VERILATOR_PARITY_MAX_CYCLES', '4000000'))
  TRACE_CYCLES = Integer(ENV.fetch('RHDL_GAMEBOY_VERILATOR_PARITY_TRACE_CYCLES', '16384'))
  TRACE_SAMPLE_EVERY = Integer(ENV.fetch('RHDL_GAMEBOY_VERILATOR_PARITY_TRACE_SAMPLE_EVERY', '128'))
  TRACE_COMPARE_LIMIT = Integer(ENV.fetch('RHDL_GAMEBOY_VERILATOR_PARITY_TRACE_COMPARE_LIMIT', '64'))
  PARITY_LEGS = %i[staged normalized raised].freeze
  DEFAULT_PARITY_LEGS = %i[staged normalized].freeze

  def announce_parity_phase!(label)
    return unless ENV['RHDL_IMPORT_PARITY_PROGRESS'] == '1'

    warn("[gameboy/import/runtime_parity_3way_verilator] #{label}")
  end

  it 'matches standard headless Verilator traces and video snapshots across staged source, normalized import, and raised RHDL', timeout: 3600 do
    require_reference_tree!
    require_tool!('ghdl')
    require_tool!('circt-verilog')
    require_tool!('verilator')
    require_pop_rom!
    require_boot_rom!

    enabled_legs = parity_leg_filter(
      env_key: 'RHDL_GAMEBOY_VERILATOR_PARITY_LEGS',
      default_legs: DEFAULT_PARITY_LEGS,
      allowed_legs: PARITY_LEGS
    )

    out_dir, workspace = stable_import_dirs('gameboy_runtime_parity_verilator')
    rom_bytes = File.binread(require_pop_rom!)
    import_gameboy!(out_dir: out_dir, workspace: workspace, emit_runtime_json: false)

    results = {}
    enabled_legs.each do |leg|
      announce_parity_phase!("collecting #{leg} capture")
      results[leg] = collect_runtime_capture_isolated(
        leg: leg,
        out_dir: out_dir,
        rom_bytes: rom_bytes,
        trace_cycles: TRACE_CYCLES,
        trace_sample_every: TRACE_SAMPLE_EVERY,
        total_cycles: MAX_CYCLES
      )
      trim_ruby_heap!
    end

    failures = []
    summary_lines = []

    enabled_legs.each do |leg|
      video = results.fetch(leg).fetch(:video)
      summary_lines << "#{leg}: #{video_summary(video)}"
      if video[:frame_count] <= 0
        failures << "#{leg} did not produce any completed frame"
      end
    end

    enabled_legs.combination(2) do |lhs, rhs|
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
            "Runtime parity summary:\n" \
            "#{summary_lines.map { |line| "  - #{line}" }.join("\n")}\n" \
            "Failures:\n" \
            "#{failures.map { |line| "  - #{line}" }.join("\n")}"
    end
  end
end
