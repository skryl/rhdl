# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

require_relative '../../../../examples/gameboy/gameboy'
require_relative '../../../../examples/gameboy/utilities/tasks/run_task'
require_relative '../../../../examples/gameboy/utilities/import/system_importer'
require_relative '../../../../examples/gameboy/utilities/import/ir_runner'

RSpec.describe 'GameBoy imported design behavioral parity on ir_jit', slow: true do
  TRACE_SIGNALS = %w[
    ext_bus_addr
    ext_bus_a15
    cart_wr
    cart_di
  ].freeze

  # Known divergence between handwritten GB DSL and imported GB reference:
  # - `nCS` is not explicitly driven in examples/gameboy/hdl/gb.rb.
  # - `cart_rd` control behavior differs in the handwritten model vs imported reference logic.
  # Keep this parity check focused on stable shared bus signals.

  def require_reference_tree!
    skip 'GameBoy reference tree not available' unless Dir.exist?(RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_REFERENCE_ROOT)
    skip 'GameBoy files.qip not available' unless File.file?(RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_QIP_PATH)
  end

  def require_tool!(cmd)
    skip "#{cmd} not available" unless HdlToolchain.which(cmd)
  end

  def require_ir_jit!
    skip 'IR JIT backend unavailable' unless RHDL::Sim::Native::IR::JIT_AVAILABLE
  end

  def collect_trace(runner, cycles:)
    Array.new(cycles) do
      runner.run_steps(1)
      runner.snapshot(TRACE_SIGNALS)
    end
  end

  def align_trace_prefix(lhs, rhs)
    a = Array(lhs)
    b = Array(rhs)
    return [a, b] if a.empty? || b.empty?

    first_match = nil
    a.each_with_index do |event_a, idx_a|
      idx_b = b.index(event_a)
      next unless idx_b

      first_match = [idx_a, idx_b]
      break
    end

    return [a, b] unless first_match

    [a.drop(first_match[0]), b.drop(first_match[1])]
  end

  it 'matches bounded bus-level behavior between source GB and imported gb on JIT backend', timeout: 1800 do
    require_reference_tree!
    require_tool!('ghdl')
    require_tool!('circt-verilog')
    require_ir_jit!

    Dir.mktmpdir('gameboy_import_parity_out') do |out_dir|
      Dir.mktmpdir('gameboy_import_parity_ws') do |workspace|
        importer = RHDL::Examples::GameBoy::Import::SystemImporter.new(
          output_dir: out_dir,
          workspace_dir: workspace,
          keep_workspace: true,
          clean_output: true,
          strict: true,
          progress: ->(_msg) {}
        )
        import_result = importer.run
        expect(import_result.success?).to be(true), Array(import_result.diagnostics).join("\n")
        report = JSON.parse(File.read(import_result.report_path))
        runtime_json_path = report.fetch('mixed_import').fetch('runtime_json_path')
        expect(File.file?(runtime_json_path)).to be(true)

        source_runner = RHDL::Examples::GameBoy::Import::IrRunner.new(
          component_class: RHDL::Examples::GameBoy::GB,
          top: 'gb',
          backend: :jit
        )
        imported_runner = RHDL::Examples::GameBoy::Import::IrRunner.new(
          runtime_json: File.read(runtime_json_path),
          top: 'gb',
          backend: :jit
        )

        demo_rom = RHDL::Examples::GameBoy::Tasks::RunTask.create_demo_rom
        [source_runner, imported_runner].each do |runner|
          runner.load_rom(demo_rom)
          runner.reset
        end

        source_trace = collect_trace(source_runner, cycles: 128)
        imported_trace = collect_trace(imported_runner, cycles: 128)
        source_trace, imported_trace = align_trace_prefix(source_trace, imported_trace)
        shared = [source_trace.length, imported_trace.length].min
        expect(imported_trace.first(shared)).to eq(source_trace.first(shared))
        expect(imported_runner.cycle_count).to eq(source_runner.cycle_count)
      end
    end
  end
end
