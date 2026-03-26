# frozen_string_literal: true

require 'spec_helper'
require 'json'

require_relative 'support'

RSpec.describe 'GameBoy import per-component semantic equivalence', slow: true do
  include_context 'gameboy import unit fixture'
  include GameBoyImportUnitSupport

  before(:context) do
    @staged_signature_cache = {}
    @raised_signature_cache = {}
    @signature_dir = File.join(gameboy_import_fixture.fetch(:workspace), 'semantic_signatures')
  end

  let(:fixture) { gameboy_import_fixture }
  let(:provenance_by_module) { gameboy_module_provenance_by_name }
  let(:expected_module_names) { fixture[:modules_by_name].keys.sort }

  def staged_signature_for(module_name)
    @staged_signature_cache[module_name] ||= normalized_module_signature_from_verilog(
      module_name,
      staged_closure_verilog_source(fixture, module_name),
      base_dir: @signature_dir,
      stem: "staged_#{module_name}"
    )
  end

  def raised_signature_for(module_name)
    @raised_signature_cache[module_name] ||= begin
      component = fixture[:raise_component_result].components.fetch(module_name)
      module_signature_from_component(component, module_name)
    end
  end

  it 'matches the expected imported module inventory on a fresh strict import' do
    expect(fixture[:modules_by_name].keys.sort).to eq(expected_module_names)
    expect(provenance_by_module.keys.sort).to eq(expected_module_names)
  end

  expected_names_for_examples = JSON.parse(
    File.read(File.expand_path('../../../../../examples/gameboy/import/import_report.json', __dir__))
  ).fetch('modules').map { |entry| entry.fetch('name') }.sort.freeze

  expected_names_for_examples.each do |module_name|
    it "preserves staged closure semantics for #{module_name} through raised RHDL", timeout: 240 do
      provenance = provenance_by_module.fetch(module_name)
      expect(provenance.fetch('verilog_module_name')).to eq(module_name)
      expect(File.file?(provenance.fetch('staged_verilog_path'))).to be(true)
      expect(File.file?(provenance.fetch('raised_rhdl_path'))).to be(true)

      expect(raised_signature_for(module_name)).to eq(staged_signature_for(module_name))
    end
  end
end
