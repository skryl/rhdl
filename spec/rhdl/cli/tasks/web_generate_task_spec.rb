# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'rhdl/codegen'

RSpec.describe RHDL::CLI::Tasks::WebGenerateTask do
  describe '#run' do
    it 'builds missing wasm first, then generates configured runner assets, and reports completion' do
      task = described_class.new
      runner_exports = [{ id: 'cpu' }, { id: 'apple2' }]
      runner_configs = [{ id: 'cpu' }, { id: 'apple2' }]

      allow(task).to receive(:wasm_backends_built?).and_return(false)
      allow(task).to receive(:ensure_dir)
      allow(task).to receive(:runner_exports).and_return(runner_exports)
      allow(task).to receive(:runner_configs).and_return(runner_configs)
      allow(task).to receive(:generate_runner_assets)
      allow(task).to receive(:write_runner_preset_module)
      allow(task).to receive(:generate_apple2_memory_assets)
      allow(task).to receive(:generate_runner_default_bin_assets)
      allow(task).to receive(:write_memory_dump_asset_module)
      allow(task).to receive(:run_build)

      expect(task).to receive(:ensure_dir).with(described_class::SCRIPT_DIR)
      expect(task).to receive(:run_build).ordered
      runner_exports.each do |runner|
        expect(task).to receive(:generate_runner_assets).with(runner).ordered
      end
      expect(task).to receive(:write_runner_preset_module).with(runner_configs)
      expect(task).to receive(:generate_apple2_memory_assets)
      expect(task).to receive(:generate_runner_default_bin_assets)
      expect(task).to receive(:write_memory_dump_asset_module)

      expect { task.run }.to output(/Web artifact generation complete/).to_stdout
    end

    it 'skips wasm build when artifacts are already present' do
      task = described_class.new

      allow(task).to receive(:wasm_backends_built?).and_return(true)
      allow(task).to receive(:ensure_dir)
      allow(task).to receive(:runner_exports).and_return([])
      allow(task).to receive(:runner_configs).and_return([])
      allow(task).to receive(:write_runner_preset_module)
      allow(task).to receive(:generate_apple2_memory_assets)
      allow(task).to receive(:generate_runner_default_bin_assets)
      allow(task).to receive(:write_memory_dump_asset_module)

      expect(task).not_to receive(:run_build)

      task.run
    end
  end

  describe '#run_build' do
    it 'builds wasm artifacts and reports completion' do
      task = described_class.new

      allow(task).to receive(:build_wasm_backends)
      allow(task).to receive(:mark_wasm_build_complete!)
      expect(task).to receive(:build_wasm_backends)
      expect(task).to receive(:mark_wasm_build_complete!)

      expect { task.run_build }.to output(/Web WASM build complete/).to_stdout
    end
  end

  describe '#mruby_artifacts_embed_rhdl?' do
    it 'returns true when mruby metadata reports embedded rhdl files' do
      task = described_class.new
      metadata_path = File.join(described_class::PKG_DIR, 'mruby.version.json')
      metadata_json = JSON.generate({ 'embedded' => { 'rhdl' => true } })

      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:file?).with(metadata_path).and_return(true)
      allow(File).to receive(:read).with(metadata_path).and_return(metadata_json)

      expect(task.send(:mruby_artifacts_embed_rhdl?)).to be(true)
    end

    it 'returns false when mruby metadata is missing embedded rhdl marker' do
      task = described_class.new
      metadata_path = File.join(described_class::PKG_DIR, 'mruby.version.json')
      metadata_json = JSON.generate({ 'embedded' => {} })

      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:file?).with(metadata_path).and_return(true)
      allow(File).to receive(:read).with(metadata_path).and_return(metadata_json)

      expect(task.send(:mruby_artifacts_embed_rhdl?)).to be(false)
    end
  end

  describe '#write_mruby_emscripten_config' do
    it 'writes emscripten config that embeds rhdl sources into wasm fs' do
      task = described_class.new
      source_dir = '/tmp/mruby-src'
      mruby_require_shim_path = described_class::MRUBY_REQUIRE_SHIM_GEM_PATH
      config_path = File.join(source_dir, described_class::MRUBY_EMSCRIPTEN_CONFIG_RELATIVE_PATH)

      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with(File.join(mruby_require_shim_path, 'mrbgem.rake')).and_return(true)

      expect(File).to receive(:write) do |path, content|
        expect(path).to eq(config_path)
        expect(content).to include("MRuby::CrossBuild.new('emscripten')")
        expect(content).to include("conf.gembox 'default'")
        expect(content).to include("conf.gem #{mruby_require_shim_path.inspect}")
        expect(content).to include("conf.linker.flags << '--embed-file'")
        expect(content).to include('@/rhdl.rb')
        expect(content).to include('@/rhdl')
      end

      returned_path = task.send(:write_mruby_emscripten_config, source_dir)
      expect(returned_path).to eq(config_path)
    end
  end

  describe '#build_source_bundle' do
    it 'builds a source bundle with rhdl and verilog content' do
      task = described_class.new
      bundle = task.send(:build_source_bundle, RHDL::HDL::AndGate, 'test-runner')

      expect(bundle[:format]).to eq('rhdl.web.component_sources.v1')
      expect(bundle[:runner]).to eq('test-runner')
      expect(bundle[:top_component_class]).to eq('RHDL::HDL::AndGate')
      expect(bundle[:components]).not_to be_empty

      and_gate = bundle[:components].find { |entry| entry[:component_class] == 'RHDL::HDL::AndGate' }
      expect(and_gate).not_to be_nil
      expect(and_gate[:rhdl_source]).to include('class AndGate')
      expect(and_gate[:verilog_source]).to include('module')
    end
  end

  describe '#normalize_component_slug' do
    it 'normalizes symbols and falls back on empty input' do
      task = described_class.new
      expect(task.send(:normalize_component_slug, 'RHDL::Examples::Apple2::CPU6502')).to eq('rhdl_examples_apple2_cpu6502')
      expect(task.send(:normalize_component_slug, '   ', 'fallback_name')).to eq('fallback_name')
    end
  end

  describe '#build_wasm_backends' do
    it 'builds dedicated compiler AOT artifacts for apple2, cpu8bit, and mos6502' do
      task = described_class.new

      allow(task).to receive(:ensure_dir)
      allow(task).to receive(:copy_ghostty_web_assets)
      allow(task).to receive(:copy_vim_wasm_assets)
      allow(task).to receive(:build_mruby_wasm)
      allow(task).to receive(:ensure_aot_ir_inputs)
      allow(task).to receive(:run_rustup_target_add!).and_return(true)
      allow(task).to receive(:build_wasm_backend)
      allow(File).to receive(:write)

      expect(task).to receive(:copy_ghostty_web_assets)
      expect(task).to receive(:copy_vim_wasm_assets)
      expect(task).to receive(:build_mruby_wasm)
      expect(task).to receive(:ensure_aot_ir_inputs)
      expect(task).to receive(:build_compiler_aot_wasm).with(
        ir_path: described_class::APPLE2_AOT_IR_PATH,
        artifact: 'ir_compiler.wasm'
      )
      expect(task).to receive(:build_compiler_aot_wasm).with(
        ir_path: described_class::CPU8BIT_AOT_IR_PATH,
        artifact: 'ir_compiler_cpu.wasm'
      )
      expect(task).to receive(:build_compiler_aot_wasm).with(
        ir_path: described_class::MOS6502_AOT_IR_PATH,
        artifact: 'ir_compiler_mos6502.wasm'
      )

      task.send(:build_wasm_backends)
    end
  end

  describe 'DEFAULT_BIN_ASSETS' do
    it 'includes mos6502 snapshot asset copied from apple2 fixtures' do
      assets = described_class::DEFAULT_BIN_ASSETS
      snapshot_asset = assets.find do |entry|
        entry[:dst].to_s.end_with?('/mos6502/memory/karateka_mem.rhdlsnap')
      end

      expect(snapshot_asset).not_to be_nil
      expect(snapshot_asset[:src]).to eq(described_class::MOS6502_DEFAULT_SNAPSHOT_SOURCE)
    end
  end
end
