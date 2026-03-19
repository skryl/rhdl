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
                   maintain_directory_structure: true, patches_dir: nil, progress: nil)
    described_class.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true,
      import_strategy: import_strategy,
      fallback_to_stubbed: fallback_to_stubbed,
      maintain_directory_structure: maintain_directory_structure,
      patches_dir: patches_dir,
      progress: progress
    ).run
  end

  def write_unified_patch(path, relpath:, removal:, addition:)
    File.write(path, <<~PATCH)
      diff --git a/#{relpath} b/#{relpath}
      --- a/#{relpath}
      +++ b/#{relpath}
      @@ -1,2 +1,2 @@
      -#{removal}
      +#{addition}
       endmodule
    PATCH
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

  it 'sanitizes git patch commands from user/global git config dependencies' do
    importer = described_class.new(output_dir: '/tmp/rhdl_ao486_out')
    status = instance_double(Process::Status, success?: true, exitstatus: 0)
    captured_env = nil

    allow(Open3).to receive(:capture3) do |*args, **kwargs|
      captured_env = args.first
      ['', '', status]
    end

    importer.send(:run_command, ['git', 'apply', 'series.patch'], chdir: '/tmp')

    expect(captured_env).to include(
      'GIT_CONFIG_GLOBAL' => '/dev/null',
      'GIT_CONFIG_NOSYSTEM' => '1'
    )
  end

  it 'always includes the selected top in the circt-verilog import command' do
    importer = described_class.new(output_dir: '/tmp/rhdl_ao486_out', top: 'custom_top')

    command = importer.send(:circt_verilog_import_command_string, '/tmp/import_all.stubbed.sv')

    expect(command).to include('circt-verilog')
    expect(command).to include('--detect-memories')
    expect(command).to include('--top\\=custom_top')
  end

  it 'raises when the ao486 circt-verilog import top is empty' do
    importer = described_class.new(output_dir: '/tmp/rhdl_ao486_out', top: '')

    expect do
      importer.send(:circt_verilog_import_extra_args)
    end.to raise_error(ArgumentError, /requires a non-empty top/)
  end

  it 'rejects a missing patches_dir' do
    expect do
      described_class.new(output_dir: '/tmp/rhdl_ao486_out', patches_dir: '/tmp/does_not_exist')
    end.to raise_error(ArgumentError, /patches_dir not found/)
  end

  it 'applies an opt-in patch series to a staged source copy only' do
    skip 'patch not available' unless HdlToolchain.which('patch')

    Dir.mktmpdir('ao486_import_patch_root') do |root|
      rtl_root = File.join(root, 'rtl')
      FileUtils.mkdir_p(rtl_root)

      source_path = File.join(rtl_root, 'system.v')
      File.write(source_path, "module system;\nendmodule\n")

      patches_dir = File.join(root, 'patches')
      FileUtils.mkdir_p(patches_dir)
      write_unified_patch(
        File.join(patches_dir, '0001-system.patch'),
        relpath: 'system.v',
        removal: 'module system;',
        addition: 'module system; wire patched_system;'
      )
      write_unified_patch(
        File.join(patches_dir, '0002-system.patch'),
        relpath: 'system.v',
        removal: 'module system; wire patched_system;',
        addition: 'module system; wire patched_system; wire patched_again;'
      )

      workspace = File.join(root, 'workspace')
      importer = described_class.new(
        source_path: source_path,
        output_dir: File.join(root, 'out'),
        workspace_dir: workspace,
        keep_workspace: true,
        patches_dir: patches_dir
      )

      diagnostics = []
      command_log = []
      prepared_source = importer.send(:prepare_import_source_tree, workspace, diagnostics: diagnostics, command_log: command_log)
      expect(prepared_source[:success]).to be(true), diagnostics.join("\n")

      prepared = importer.send(:prepare_workspace, workspace, strategy: :stubbed)
      expect(File.read(source_path)).to eq("module system;\nendmodule\n")
      expect(File.read(prepared[:staged_system_path])).to include('patched_system')
      expect(File.read(prepared[:staged_system_path])).to include('patched_again')
      expect(command_log.any? { |cmd| cmd.include?('patch --dry-run --batch -p1 -i') }).to be(true)
      expect(command_log.any? { |cmd| cmd.include?('patch --batch -p1 -i') && !cmd.include?('--dry-run') }).to be(true)
    end
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
          cmd.include?(RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL) &&
            cmd.include?(RHDL::Codegen::CIRCT::Tooling::DEFAULT_CIRCT_VERILOG_IMPORT_MODE) &&
            cmd.include?('--top\\=system')
        end).to be(true)
        expect(result.command_log.none? { |cmd| cmd.include?('--import-verilog') }).to be(true)
      end
    end
  end

  it 'reports staged Verilog, MLIR, and raised RHDL package sizes through progress output', timeout: 120 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_import_out') do |out_dir|
      Dir.mktmpdir('ao486_import_ws') do |workspace|
        progress = []
        result = run_importer(
          out_dir: out_dir,
          workspace: workspace,
          progress: lambda { |message| progress << message }
        )

        expect(result.success?).to be(true), diagnostic_summary(result)
        expect(progress.any? { |line| line.include?('staged pure Verilog package files=') && line.include?('size=') }).to be(true)
        expect(progress.any? { |line| line.include?('moore MLIR') && line.include?('size=') }).to be(true)
        expect(progress.any? { |line| line.include?('core MLIR') && line.include?('size=') }).to be(true)
        expect(progress.any? { |line| line.include?('normalized core MLIR') && line.include?('size=') }).to be(true)
        expect(progress.any? { |line| line.include?('raised RHDL package files=') && line.include?('size=') }).to be(true)
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
