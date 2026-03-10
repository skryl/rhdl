# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../lib/rhdl/codegen/circt/tooling'

RSpec.describe 'AO486 imported CPU Arcilator compile', slow: true do
  def require_tools!
    import_tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
    skip "#{import_tool} not available" unless HdlToolchain.which(import_tool)
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'arcilator not available' unless HdlToolchain.which('arcilator')
  end

  it 'builds Arcilator artifacts from the imported CPU top without staged AO486 patches', timeout: 600 do
    require_tools!

    Dir.mktmpdir('ao486_cpu_arcilator_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_arcilator_ws') do |workspace|
        import_result = RHDL::Examples::AO486::Import::CpuImporter.new(
          output_dir: out_dir,
          workspace_dir: workspace,
          keep_workspace: true,
          maintain_directory_structure: false
        ).run

        expect(import_result.success?).to be(true), Array(import_result.diagnostics).join("\n")

        prepared = RHDL::Codegen::CIRCT::Tooling.prepare_arc_mlir_from_circt_mlir(
          mlir_path: import_result.normalized_core_mlir_path,
          work_dir: File.join(out_dir, 'arc'),
          base_name: 'ao486_cpu',
          top: 'ao486'
        )

        expect(prepared[:success]).to be(true), prepared.dig(:arc, :stderr).to_s
        expect(prepared.dig(:flatten, :success)).to be(true), prepared.dig(:flatten, :stderr).to_s
        expect(File.exist?(prepared.fetch(:flattened_hwseq_mlir_path))).to be(true)

        ll_path = File.join(out_dir, 'arc', 'ao486_cpu.ll')
        state_path = File.join(out_dir, 'arc', 'ao486_cpu.state.json')
        command = [
          'arcilator',
          prepared.fetch(:arc_mlir_path),
          '--observe-registers',
          "--state-file=#{state_path}",
          '-o',
          ll_path
        ]

        expect(system(*command)).to be(true), "arcilator failed for #{prepared.fetch(:arc_mlir_path)}"
        expect(File.exist?(ll_path)).to be(true)
        expect(File.exist?(state_path)).to be(true)
      end
    end
  end
end
