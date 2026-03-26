# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require 'rhdl/codegen'

RSpec.describe 'RHDL source/schematic exports' do
  describe RHDL::Codegen::Source do
    it 'exports a component entry with source path and contents' do
      entry = described_class.component_entry(
        RHDL::HDL::AndGate,
        relative_to: File.expand_path('../../..', __dir__)
      )

      expect(entry[:component_class]).to eq('RHDL::HDL::AndGate')
      expect(entry[:source_path]).to end_with('lib/rhdl/hdl/gates/and_gate.rb')
      expect(entry[:rhdl_source]).to include('class AndGate')
      expect(entry[:module_name]).to eq('and_gate')
    end

    it 'builds a bundle with a top entry and sorted components' do
      bundle = described_class.bundle(RHDL::HDL::AndGate, runner: 'and-gate')

      expect(bundle[:format]).to eq('rhdl.web.component_sources.v1')
      expect(bundle[:runner]).to eq('and-gate')
      expect(bundle[:top_component_class]).to eq('RHDL::HDL::AndGate')
      expect(bundle[:top][:component_class]).to eq('RHDL::HDL::AndGate')
      expect(bundle[:components].map { |entry| entry[:component_class] }).to eq(
        bundle[:components].map { |entry| entry[:component_class] }.sort
      )
    end
  end

  describe RHDL::Codegen::Schematic do
    it 'uses flattened CIRCT nodes for class-level schematic default IR' do
      expect(RHDL::HDL::AndGate).to receive(:to_flat_circt_nodes).and_call_original

      bundle = RHDL::HDL::AndGate.to_schematic(runner: 'and-gate')
      expect(bundle[:format]).to eq('rhdl.web.schematic.v1')
    end

    it 'exports a schematic bundle for a component hierarchy' do
      bundle = described_class.bundle(
        top_class: RHDL::HDL::AndGate,
        sim_ir: RHDL::HDL::AndGate.to_circt_runtime_json,
        runner: 'and-gate'
      )

      expect(bundle[:format]).to eq('rhdl.web.schematic.v1')
      expect(bundle[:runner]).to eq('and-gate')
      expect(bundle[:top_path]).to eq('top')
      expect(bundle[:components]).not_to be_empty

      top = bundle[:components].find { |component| component[:path] == 'top' }
      expect(top).not_to be_nil
      expect(top[:name]).to eq('top')
      expect(top[:schematic][:symbols].map { |symbol| symbol[:type] }).to include('focus', 'io', 'op')
      expect(top[:schematic][:wires].map { |wire| wire[:kind] }).to include('assign_source')
      expect(top[:schematic][:nets].find { |net| net[:name] == 'a0' }[:live_name]).to eq('a0')
      expect(top[:schematic][:wires]).not_to be_empty
      expect(top[:schematic][:nets]).not_to be_empty
    end

    it 'rejects malformed CIRCT runtime wrapper payloads' do
      expect do
        described_class.bundle(
          top_class: RHDL::HDL::AndGate,
          sim_ir: { 'circt_json_version' => 1 },
          runner: 'and-gate'
        )
      end.to raise_error(ArgumentError, /circt_json_version and non-empty modules/)
    end
  end
end
