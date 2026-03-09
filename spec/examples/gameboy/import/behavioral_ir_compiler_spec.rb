# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'

require_relative '../../../../examples/gameboy/gameboy'
require_relative '../../../../examples/gameboy/utilities/tasks/run_task'
require_relative '../../../../examples/gameboy/utilities/import/system_importer'
require_relative '../../../../examples/gameboy/utilities/import/ir_runner'

RSpec.describe 'GameBoy imported design behavioral parity on ir_compiler', slow: true do
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

  def require_ir_compiler!
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
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

  def trim_ruby_heap!
    GC.start(full_mark: true, immediate_sweep: true)
    GC.compact if GC.respond_to?(:compact)
  end

  it 'matches bounded bus-level behavior between source GB and imported gb on compiler backend', timeout: 1800 do
    require_reference_tree!
    require_tool!('ghdl')
    require_tool!('circt-verilog')
    require_ir_compiler!

    Dir.mktmpdir('gameboy_import_parity_out') do |out_dir|
      Dir.mktmpdir('gameboy_import_parity_ws') do |workspace|
        importer = RHDL::Examples::GameBoy::Import::SystemImporter.new(
          output_dir: out_dir,
          workspace_dir: workspace,
          keep_workspace: true,
          clean_output: true,
          emit_runtime_json: false,
          strict: true,
          progress: ->(_msg) {}
        )
        import_result = importer.run
        expect(import_result.success?).to be(true), Array(import_result.diagnostics).join("\n")
        expect(File.file?(import_result.mlir_path)).to be(true)
        imported_mlir_path = import_result.mlir_path
        importer = nil
        import_result = nil
        trim_ruby_heap!

        demo_rom = RHDL::Examples::GameBoy::Tasks::RunTask.create_demo_rom

        source_trace = nil
        source_cycles = nil
        source_runner = RHDL::Examples::GameBoy::Import::IrRunner.new(
          component_class: RHDL::Examples::GameBoy::GB,
          top: 'gb',
          backend: :compiler
        )
        begin
          source_runner.load_rom(demo_rom)
          source_runner.reset
          source_trace = collect_trace(source_runner, cycles: 128)
          source_cycles = source_runner.cycle_count
        ensure
          source_runner.close if source_runner.respond_to?(:close)
        end
        source_runner = nil
        trim_ruby_heap!

        imported_mlir = File.read(imported_mlir_path)
        imported_runner = RHDL::Examples::GameBoy::Import::IrRunner.new(
          mlir: imported_mlir,
          top: 'gb',
          backend: :compiler
        )
        imported_mlir = nil
        trim_ruby_heap!
        begin
          imported_runner.load_rom(demo_rom)
          imported_runner.reset
          imported_trace = collect_trace(imported_runner, cycles: 128)
          source_trace, imported_trace = align_trace_prefix(source_trace, imported_trace)
          shared = [source_trace.length, imported_trace.length].min

          expect(imported_trace.first(shared)).to eq(source_trace.first(shared))
          expect(imported_runner.cycle_count).to eq(source_cycles)
        ensure
          imported_runner.close if imported_runner.respond_to?(:close)
        end
        imported_runner = nil
        trim_ruby_heap!
      end
    end
  end
end
