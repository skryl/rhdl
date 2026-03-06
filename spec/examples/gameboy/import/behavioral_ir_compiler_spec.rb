# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

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

  it 'matches bounded bus-level behavior between source GB and imported gb on compile backend', timeout: 1800 do
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
          strict: true,
          progress: ->(_msg) {}
        )
        import_result = importer.run
        expect(import_result.success?).to be(true), Array(import_result.diagnostics).join("\n")

        source_runner = RHDL::Examples::GameBoy::Import::IrRunner.new(
          component_class: RHDL::Examples::GameBoy::GB,
          top: 'gb',
          backend: :compile
        )
        imported_runner = RHDL::Examples::GameBoy::Import::IrRunner.new(
          mlir: File.read(import_result.mlir_path),
          top: 'gb',
          backend: :compile
        )

        demo_rom = RHDL::Examples::GameBoy::Tasks::RunTask.create_demo_rom
        [source_runner, imported_runner].each do |runner|
          runner.load_rom(demo_rom)
          runner.reset
        end

        source_trace = collect_trace(source_runner, cycles: 128)
        imported_trace = collect_trace(imported_runner, cycles: 128)
        expect(imported_trace).to eq(source_trace)
        expect(imported_runner.cycle_count).to eq(source_runner.cycle_count)
      end
    end
  end
end
