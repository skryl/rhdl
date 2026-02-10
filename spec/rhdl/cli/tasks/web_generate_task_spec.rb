# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'rhdl/codegen'

RSpec.describe RHDL::CLI::Tasks::WebGenerateTask do
  describe '#run' do
    it 'creates output dir, generates each configured runner, and reports completion' do
      task = described_class.new
      allow(task).to receive(:ensure_dir)
      allow(task).to receive(:generate_runner_assets)
      allow(task).to receive(:generate_apple2_memory_assets)
      allow(task).to receive(:build_wasm_backends)

      expect(task).to receive(:ensure_dir).with(described_class::SCRIPT_DIR)
      described_class::RUNNER_EXPORTS.each do |runner|
        expect(task).to receive(:generate_runner_assets).with(runner)
      end
      expect(task).to receive(:generate_apple2_memory_assets)
      expect(task).to receive(:build_wasm_backends)

      expect { task.run }.to output(/Web artifact generation complete/).to_stdout
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
end
