# frozen_string_literal: true

require 'spec_helper'
require 'json'

require_relative 'support'

RSpec.describe 'GameBoy imported per-component raised RHDL', slow: true do
  include GameBoyImportUnitSupport

  RAISE_DEGRADE_OPS = %w[
    raise.behavior
    raise.expr
    raise.memory_read
    raise.case
    raise.sequential
    raise.sequential_if
  ].freeze

  before(:context) do
    @fixture = build_gameboy_import_fixture
    @raised_signature_cache = {}
  end

  after(:context) do
    cleanup_gameboy_import_fixture(@fixture)
  end

  let(:fixture) { @fixture }
  let(:provenance_by_module) { component_provenance_by_module(fixture[:report]) }
  let(:expected_module_names) { fixture[:modules_by_name].keys.sort }

  def raised_component_signature(module_name)
    @raised_signature_cache[module_name] ||= begin
      component = fixture[:raise_component_result].components.fetch(module_name)
      module_signature_from_component(component, module_name)
    end
  end

  it 'matches the expected imported module inventory on a fresh strict import' do
    expect(fixture[:modules_by_name].keys.sort).to eq(expected_module_names)
  end

  it 'emits deterministic per-component provenance for the full imported module set' do
    expect(provenance_by_module.keys.sort).to eq(expected_module_names)
  end

  it 'raises the imported package without degrade diagnostics' do
    degrade_diags = Array(fixture[:raise_source_result].diagnostics) + Array(fixture[:raise_component_result].diagnostics)
    degrade_diags = degrade_diags.select { |diag| RAISE_DEGRADE_OPS.include?(diag.respond_to?(:op) ? diag.op.to_s : nil) }
    expect(degrade_diags).to be_empty, degrade_diags.map(&:message).join("\n")
  end

  expected_names_for_examples = JSON.parse(
    File.read(File.expand_path('../../../../../examples/gameboy/import/import_report.json', __dir__))
  ).fetch('modules').map { |entry| entry.fetch('name') }.sort.freeze

  expected_names_for_examples.each do |module_name|
    it "raises #{module_name} with stable naming, highest-available DSL markers, and semantic parity", timeout: 240 do
      mod = fixture[:modules_by_name].fetch(module_name)
      provenance = provenance_by_module.fetch(module_name)
      raised_path = provenance.fetch('raised_rhdl_path')
      expected_basename = "#{RHDL::Codegen::CIRCT::Raise.send(:underscore, module_name)}.rb"
      raised_source = fixture[:raise_source_result].sources.fetch(module_name)
      expected_signature = semantic_signature_for_module(mod)
      expected_dsl = provenance.fetch('expected_dsl_features')

      expect(File.file?(raised_path)).to be(true)
      expect(File.basename(raised_path)).to eq(expected_basename)
      expect(provenance.fetch('ruby_class_name')).to eq(RHDL::Codegen::CIRCT::Raise.send(:camelize, module_name))
      expect(raised_source).to include("class #{RHDL::Codegen::CIRCT::Raise.send(:camelize, module_name)}")
      expect(raised_source).to include(%("#{module_name}"))

      if expected_dsl.fetch('sequential')
        expect(raised_source).to include('RHDL::Sim::SequentialComponent')
        expect(raised_source).to include('include RHDL::DSL::Sequential')
        expect(raised_source).to include('sequential clock:')
      else
        expect(raised_source).not_to include('include RHDL::DSL::Sequential')
      end

      if Array(mod.instances).any?
        expect(raised_source).to include('instance :')
      end

      if expected_dsl.fetch('behavior')
        expect(raised_source).to include('behavior do')
      else
        expect(raised_source).not_to include('behavior do')
      end

      if expected_dsl.fetch('memory')
        expect(raised_source).to include('include RHDL::DSL::Memory')
      else
        expect(raised_source).not_to include('include RHDL::DSL::Memory')
      end

      expect(Array(provenance['emitted_dsl_features']).include?('behavior')).to eq(expected_dsl.fetch('behavior'))
      expect(Array(provenance['emitted_dsl_features']).include?('sequential')).to eq(expected_dsl.fetch('sequential'))
      expect(Array(provenance['emitted_dsl_features']).include?('memory')).to eq(expected_dsl.fetch('memory'))
      expect(raised_component_signature(module_name)).to eq(expected_signature)
    end
  end
end
