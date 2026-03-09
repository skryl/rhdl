# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'fileutils'
require 'timeout'

require_relative '../../../../examples/gameboy/utilities/import/system_importer'

RSpec.describe 'GameBoy mixed import path coverage', slow: true do
  IMPORT_TIMEOUT_SECONDS = 1800

  def require_reference_tree!
    skip 'GameBoy reference tree not available' unless Dir.exist?(RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_REFERENCE_ROOT)
    skip 'GameBoy files.qip not available' unless File.file?(RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_QIP_PATH)
  end

  def require_tool!(cmd)
    skip "#{cmd} not available" unless HdlToolchain.which(cmd)
  end

  before(:context) do
    require_reference_tree!
    require_tool!('ghdl')
    require_tool!('circt-verilog')

    @out_dir = Dir.mktmpdir('gameboy_import_paths_out')
    @workspace = Dir.mktmpdir('gameboy_import_paths_ws')
    @import_setup_error = nil

    importer = RHDL::Examples::GameBoy::Import::SystemImporter.new(
      output_dir: @out_dir,
      workspace_dir: @workspace,
      keep_workspace: true,
      clean_output: true,
      strict: true,
      progress: ->(_msg) {}
    )

    begin
      Timeout.timeout(IMPORT_TIMEOUT_SECONDS) do
        @result = importer.run
        @report = JSON.parse(File.read(@result.report_path)) if @result&.report_path && File.file?(@result.report_path)
      end
    rescue StandardError => e
      @import_setup_error = e
    end
  end

  after(:context) do
    FileUtils.rm_rf(@out_dir) if @out_dir
    FileUtils.rm_rf(@workspace) if @workspace
  end

  def result
    @result
  end

  def report
    @report
  end

  def mixed
    report.fetch('mixed_import')
  end

  def artifacts
    report.fetch('artifacts')
  end

  def out_dir
    @out_dir
  end

  def workspace
    @workspace
  end

  def require_successful_import!
    raise @import_setup_error if @import_setup_error

    expect(result).not_to be_nil
    expect(result.success?).to be(true), Array(result.diagnostics).join("\n")
    expect(result.strategy_used).to eq(:mixed)
    expect(report).not_to be_nil
  end

  it 'completes a strict mixed import successfully' do
    require_successful_import!

    expect(report.fetch('success')).to be(true)
    expect(report.fetch('strict')).to be(true)
    expect(report.fetch('top')).to eq('gb')
  end

  it 'writes mixed import artifacts into stable output and workspace roots' do
    require_successful_import!

    pure_root = mixed.fetch('pure_verilog_root')
    staged_entry = mixed.fetch('pure_verilog_entry_path')
    runtime_json = mixed.fetch('runtime_json_path')
    firtool_verilog = mixed.fetch('firtool_verilog_path')
    normalized_verilog = mixed.fetch('normalized_verilog_path')
    workspace_runtime_json = artifacts.fetch('workspace_runtime_json_path')
    workspace_firtool_verilog = artifacts.fetch('workspace_firtool_verilog_path')
    workspace_normalized_verilog = artifacts.fetch('workspace_normalized_verilog_path')
    workspace_core_mlir = artifacts.fetch('workspace_core_mlir_path')

    expect(File.file?(staged_entry)).to be(true)
    expect(File.file?(runtime_json)).to be(true)
    expect(File.file?(firtool_verilog)).to be(true)
    expect(File.file?(normalized_verilog)).to be(true)
    expect(File.file?(workspace_runtime_json)).to be(true)
    expect(File.file?(workspace_firtool_verilog)).to be(true)
    expect(File.file?(workspace_normalized_verilog)).to be(true)
    expect(File.file?(workspace_core_mlir)).to be(true)
    expect(staged_entry).to start_with(File.join(out_dir, '.mixed_import'))
    expect(runtime_json).to start_with(File.join(out_dir, '.mixed_import'))
    expect(firtool_verilog).to start_with(File.join(out_dir, '.mixed_import'))
    expect(normalized_verilog).to start_with(File.join(out_dir, '.mixed_import'))
    expect(pure_root).to start_with(File.join(out_dir, '.mixed_import'))
    expect(workspace_runtime_json).to start_with(File.join(workspace, 'import_artifacts'))
    expect(workspace_firtool_verilog).to start_with(File.join(workspace, 'import_artifacts'))
    expect(workspace_normalized_verilog).to start_with(File.join(workspace, 'import_artifacts'))
    expect(workspace_core_mlir).to start_with(File.join(workspace, 'import_artifacts'))
  end

  it 'keeps artifact aliases consistent between report sections' do
    require_successful_import!

    expect(artifacts.fetch('pure_verilog_root')).to eq(mixed.fetch('pure_verilog_root'))
    expect(artifacts.fetch('pure_verilog_entry_path')).to eq(mixed.fetch('pure_verilog_entry_path'))
    expect(artifacts.fetch('core_mlir_path')).to eq(mixed.fetch('core_mlir_path'))
    expect(artifacts.fetch('runtime_json_path')).to eq(mixed.fetch('runtime_json_path'))
    expect(artifacts.fetch('firtool_verilog_path')).to eq(mixed.fetch('firtool_verilog_path'))
    expect(artifacts.fetch('normalized_verilog_path')).to eq(mixed.fetch('normalized_verilog_path'))
    expect(mixed.fetch('workspace_runtime_json_path')).to eq(artifacts.fetch('workspace_runtime_json_path'))
    expect(mixed.fetch('workspace_firtool_verilog_path')).to eq(artifacts.fetch('workspace_firtool_verilog_path'))
    expect(mixed.fetch('workspace_normalized_verilog_path')).to eq(artifacts.fetch('workspace_normalized_verilog_path'))
    expect(mixed.fetch('workspace_core_mlir_path')).to eq(artifacts.fetch('workspace_core_mlir_path'))
  end

  it 'does not leak transient mixed source paths into the staged entry file' do
    require_successful_import!

    staged_content = File.read(mixed.fetch('pure_verilog_entry_path'))
    expect(staged_content).to include(mixed.fetch('pure_verilog_root'))
    expect(staged_content).not_to include(File.join(workspace, 'mixed_sources'))
  end

  it 'keeps the staged runtime entry importable by circt-verilog' do
    require_successful_import!

    runtime_import_mlir = File.join(workspace, 'runtime_entry.core.mlir')
    runtime_import = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
      verilog_path: mixed.fetch('pure_verilog_entry_path'),
      out_path: runtime_import_mlir,
      tool: 'circt-verilog'
    )

    expect(runtime_import[:success]).to be(true), <<~MSG
      Runtime staged Verilog should remain importable after path stabilization.
      Command: #{runtime_import[:command]}
      #{runtime_import[:stderr]}
    MSG
    expect(File.file?(runtime_import_mlir)).to be(true)
  end

  it 'applies the video wire rewrite regression fix' do
    require_successful_import!

    video_source = File.join(mixed.fetch('pure_verilog_root'), 'rtl', 'video.v')
    skip 'video.v not present in staged pure Verilog tree' unless File.file?(video_source)

    video_text = File.read(video_source)
    expect(video_text).to include('wire [7:0] spr_extra_tile0;')
    expect(video_text).to include('wire [7:0] spr_extra_tile1;')
    expect(video_text).not_to include('spr_extra_tile [0:1]')
  end

  it 'emits no import or raise error diagnostics' do
    require_successful_import!

    import_errors = Array(report.fetch('import_diagnostics', [])).select { |diag| diag['severity'] == 'error' }
    raise_errors = Array(report.fetch('raise_diagnostics', [])).select { |diag| diag['severity'] == 'error' }

    expect(import_errors).to be_empty
    expect(raise_errors).to be_empty
  end
end
