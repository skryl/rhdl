# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

require_relative './headless_runtime_support'

RSpec.describe 'GameBoy mixed import runtime parity (HeadlessRunner/VerilatorRunner/VerilatorRunner/IrRunner)', slow: true do
  include GameboyImportHeadlessRuntimeSupport

  MAX_CYCLES = Integer(ENV.fetch('RHDL_GAMEBOY_RUNTIME_PARITY_MAX_CYCLES', '250000'))
  TRACE_CYCLES = Integer(ENV.fetch('RHDL_GAMEBOY_RUNTIME_PARITY_TRACE_CYCLES', '16384'))
  TRACE_SAMPLE_EVERY = Integer(ENV.fetch('RHDL_GAMEBOY_RUNTIME_PARITY_TRACE_SAMPLE_EVERY', '128'))
  TRACE_COMPARE_LIMIT = Integer(ENV.fetch('RHDL_GAMEBOY_RUNTIME_PARITY_TRACE_COMPARE_LIMIT', '64'))
  PARITY_LEGS = %i[staged normalized ir].freeze

  def require_non_verilator_parity_enabled!
    return if ENV['RHDL_ENABLE_NON_VERILATOR_GAMEBOY_PARITY'] == '1'

    skip 'Non-Verilator Game Boy parity backends are opt-in; set RHDL_ENABLE_NON_VERILATOR_GAMEBOY_PARITY=1 to run this spec'
  end

  def announce_parity_phase!(label)
    return unless ENV['RHDL_IMPORT_PARITY_PROGRESS'] == '1'

    warn("[gameboy/import/runtime_parity_3way] #{label}")
  end

  it 'matches standard headless traces and video snapshots across staged Verilator, normalized Verilator, and IR compiler', timeout: 3600 do
    require_non_verilator_parity_enabled!
    require_reference_tree!
    require_tool!('ghdl')
    require_tool!('circt-verilog')
    require_tool!('verilator')
    require_pop_rom!
    require_boot_rom!
    require_ir_compiler!

    Dir.mktmpdir('gameboy_runtime_parity_out') do |out_dir|
      Dir.mktmpdir('gameboy_runtime_parity_ws') do |workspace|
        rom_bytes = File.binread(require_pop_rom!)
        import_gameboy!(out_dir: out_dir, workspace: workspace)

        results = {}
        PARITY_LEGS.each do |leg|
          announce_parity_phase!("collecting #{leg} capture")
          with_headless_runner(leg: leg, out_dir: out_dir) do |headless|
            results[leg] = collect_runtime_capture(
              headless,
              rom_bytes: rom_bytes,
              trace_cycles: TRACE_CYCLES,
              trace_sample_every: TRACE_SAMPLE_EVERY,
              total_cycles: MAX_CYCLES
            )
          end
          trim_ruby_heap!
        end

        failures = []
        summary_lines = []

        PARITY_LEGS.each do |leg|
          video = results.fetch(leg).fetch(:video)
          summary_lines << "#{leg}: frames=#{video[:frame_count]} nonzero=#{video[:nonzero_pixels]} hash=#{video[:hash]}"
        end

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
                "Runtime parity summary:\n" \
                "#{summary_lines.map { |line| "  - #{line}" }.join("\n")}\n" \
                "Failures:\n" \
                "#{failures.map { |line| "  - #{line}" }.join("\n")}"
        end
      end
    end
  end
end
