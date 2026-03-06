# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/system_importer'

RSpec.describe RHDL::Examples::AO486::Import::SystemImporter do
  def require_import_tool!
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
    skip "#{tool} not available" unless HdlToolchain.which(tool)
  end

  def diagnostic_summary(result)
    lines = []
    diagnostics = result.respond_to?(:diagnostics) ? Array(result.diagnostics) : []
    lines.concat(diagnostics)
    extra_raise = result.respond_to?(:raise_diagnostics) ? Array(result.raise_diagnostics) : []
    extra_raise.each do |diag|
      lines << "[#{diag.severity}]#{diag.op ? " #{diag.op}:" : ''} #{diag.message}"
    end
    lines.join("\n")
  end

  def run_importer(out_dir:, workspace:, import_strategy: :stubbed, fallback_to_stubbed: true,
                   maintain_directory_structure: true)
    described_class.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true,
      import_strategy: import_strategy,
      fallback_to_stubbed: fallback_to_stubbed,
      maintain_directory_structure: maintain_directory_structure
    ).run
  end

  it 'rejects unknown import strategies' do
    expect do
      described_class.new(output_dir: '/tmp/rhdl_ao486_out', import_strategy: :unknown)
    end.to raise_error(ArgumentError, /Unknown AO486 import strategy/)
  end

  it 'requires output_dir' do
    expect do
      described_class.new(output_dir: nil)
    end.to raise_error(ArgumentError, /output_dir is required/)
  end

  it 'cleans all existing output directory contents' do
    Dir.mktmpdir('ao486_import_out_clean') do |out_dir|
      FileUtils.mkdir_p(File.join(out_dir, 'nested', 'deep'))
      FileUtils.mkdir_p(File.join(out_dir, '.hidden_dir'))
      File.write(File.join(out_dir, 'stale.rb'), '# stale')
      File.write(File.join(out_dir, 'stale.json'), '{"stale":true}')
      File.write(File.join(out_dir, '.stale_marker'), 'x')
      File.write(File.join(out_dir, 'nested', 'deep', 'stale.txt'), 'x')

      importer = described_class.new(output_dir: out_dir)
      importer.send(:clean_output_dir!)

      expect(Dir.children(out_dir)).to be_empty
    end
  end

  it 'imports system.v through CIRCT and raises DSL files', timeout: 120 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_import_out') do |out_dir|
      Dir.mktmpdir('ao486_import_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)

        expect(result.success?).to be(true), diagnostic_summary(result)
        expect(result.strategy_requested).to eq(:stubbed)
        expect(result.strategy_used).to eq(:stubbed)
        expect(result.fallback_used).to be(false)
        expect(result.files_written.map { |path| File.basename(path) }).to include('system.rb')

        system_rb = File.join(out_dir, 'system.rb')
        expect(File.exist?(system_rb)).to be(true)
        expect(File.read(system_rb)).to include('class System < RHDL::Sim::SequentialComponent')
        expect(File.exist?(File.join(out_dir, 'ao486', 'ao486.rb'))).to be(true)

        normalized_mlir = result.normalized_core_mlir_path
        expect(normalized_mlir).not_to be_nil
        expect(File.exist?(normalized_mlir)).to be(true)
        expect(File.read(normalized_mlir)).to include('hw.module @system')
      end
    end
  end

  it 'produces core CIRCT artifacts from Verilog system.v import', timeout: 120 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_import_out') do |out_dir|
      Dir.mktmpdir('ao486_import_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        expect(result.success?).to be(true), diagnostic_summary(result)

        expect(File.exist?(result.moore_mlir_path)).to be(true)
        expect(File.exist?(result.core_mlir_path)).to be(true)
        expect(File.exist?(result.normalized_core_mlir_path)).to be(true)

        normalized = File.read(result.normalized_core_mlir_path)
        expect(normalized).to include('hw.module @system')
        expect(normalized).not_to include('hw.module private @')

        expect(result.command_log.any? do |cmd|
          cmd.start_with?("#{RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL} ")
        end).to be(true)
        expect(result.command_log.none? { |cmd| cmd.start_with?('circt-translate ') }).to be(true)
      end
    end
  end

  it 'round-trips raised AO486 system back to CIRCT MLIR', timeout: 120 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_import_out') do |out_dir|
      Dir.mktmpdir('ao486_import_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        expect(result.success?).to be(true), diagnostic_summary(result)

        components = RHDL::Codegen.raise_circt_components(
          File.read(result.normalized_core_mlir_path),
          top: 'system'
        )
        expect(components.success?).to be(true), diagnostic_summary(components)
        expect(components.components).to include('system')

        system_mlir = components.components.fetch('system').to_ir(top_name: 'system')
        expect(system_mlir).to include('hw.module @system')

        import_result = RHDL::Codegen.import_circt_mlir(system_mlir)
        expect(import_result.success?).to be(true), diagnostic_summary(import_result)
        expect(import_result.modules.map(&:name)).to include('system')
      end
    end
  end

  it 'attempts tree strategy and falls back to stubbed when needed', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_import_out') do |out_dir|
      Dir.mktmpdir('ao486_import_ws') do |workspace|
        result = run_importer(
          out_dir: out_dir,
          workspace: workspace,
          import_strategy: :tree,
          fallback_to_stubbed: true
        )

        expect(result.success?).to be(true), diagnostic_summary(result)
        expect(result.strategy_requested).to eq(:tree)
        expect(result.attempted_strategies).to include(:tree)
        expect(%i[tree stubbed]).to include(result.strategy_used)
        expect(File.basename(result.normalized_core_mlir_path)).to match(/system\.(tree|stubbed)\.normalized\.core\.mlir/)

        if result.strategy_used == :stubbed
          expect(result.fallback_used).to be(true)
          expect(Array(result.diagnostics).join("\n")).to include("retrying with 'stubbed'")
        end
      end
    end
  end

  it 'does not fallback when tree strategy is requested with fallback disabled', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_import_out') do |out_dir|
      Dir.mktmpdir('ao486_import_ws') do |workspace|
        result = run_importer(
          out_dir: out_dir,
          workspace: workspace,
          import_strategy: :tree,
          fallback_to_stubbed: false
        )

        expect(result.success?).to be(true), diagnostic_summary(result)
        expect(result.strategy_requested).to eq(:tree)
        expect(result.strategy_used).to eq(:tree)
        expect(result.fallback_used).to be(false)
        expect(result.attempted_strategies).to eq([:tree])
        expect(Array(result.diagnostics).join("\n")).not_to include("retrying with 'stubbed'")
        expect(File.exist?(File.join(out_dir, 'ao486', 'pipeline', 'pipeline.rb'))).to be(true)
      end
    end
  end

  it 'can disable directory mirroring for tree strategy output', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_import_out') do |out_dir|
      Dir.mktmpdir('ao486_import_ws') do |workspace|
        result = run_importer(
          out_dir: out_dir,
          workspace: workspace,
          import_strategy: :tree,
          fallback_to_stubbed: false,
          maintain_directory_structure: false
        )

        expect(result.success?).to be(true), diagnostic_summary(result)
        expect(File.exist?(File.join(out_dir, 'pipeline.rb'))).to be(true)
        expect(Dir.glob(File.join(out_dir, '**', '*.rb')).all? do |path|
                 File.dirname(path) == out_dir
               end).to be(true)
      end
    end
  end

  it 'can disable directory mirroring for stubbed strategy output', timeout: 120 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_import_out') do |out_dir|
      Dir.mktmpdir('ao486_import_ws') do |workspace|
        result = run_importer(
          out_dir: out_dir,
          workspace: workspace,
          import_strategy: :stubbed,
          maintain_directory_structure: false
        )

        expect(result.success?).to be(true), diagnostic_summary(result)
        expect(File.exist?(File.join(out_dir, 'ao486.rb'))).to be(true)
        expect(File.exist?(File.join(out_dir, 'ao486', 'ao486.rb'))).to be(false)
      end
    end
  end
end
