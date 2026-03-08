# frozen_string_literal: true

require 'spec_helper'
require 'pathname'

require_relative '../../../../../lib/rhdl/cli/tasks/import_task'
require_relative 'support'

RSpec.describe 'GameBoy import staged Verilog mapping', slow: true do
  include GameBoyImportUnitSupport

  before(:context) do
    @fixture = build_gameboy_import_fixture
  end

  after(:context) do
    cleanup_gameboy_import_fixture(@fixture)
  end

  def fixture
    @fixture
  end

  def component_manifest
    component_provenance_entries(fixture[:report])
  end

  it 'covers the full imported module inventory with deterministic component metadata' do
    manifest_names = component_manifest.map { |entry| entry.fetch('module_name') }.sort
    imported_names = fixture[:modules_by_name].keys.sort

    expect(manifest_names).to eq(imported_names)
  end

  def assert_staged_module_matches_source(module_name)
    component = component_provenance_by_module(fixture[:report]).fetch(module_name)
    staged_path = component.fetch('staged_verilog_path')
    staged_module_name = component.fetch('staged_verilog_module_name')

    expect(File.file?(staged_path)).to be(true), staged_path
    expect(module_names_in_file(staged_path)).to include(staged_module_name)
    expect(staged_module_name).to eq(module_name)

    actual_signature = normalized_module_signature_from_verilog(
      module_name,
      staged_closure_verilog_source(fixture, module_name),
      base_dir: File.join(fixture[:workspace], 'staged_signature_checks'),
      stem: "actual_#{module_name}"
    )

    expected_signature = normalized_module_signature_from_verilog(
      module_name,
      original_closure_verilog_source(fixture, module_name),
      base_dir: File.join(fixture[:workspace], 'staged_signature_checks'),
      stem: "expected_#{module_name}"
    )

    expect(actual_signature).to eq(expected_signature)
  end

  it 'preserves staged Verilog semantics for every imported module', timeout: 240 do
    fixture[:modules_by_name].keys.sort.each do |module_name|
      aggregate_failures(module_name) do
        assert_staged_module_matches_source(module_name)
      end
    end
  end

  # Keep one focused per-component example for easier triage on direct reruns.
  fixture_names_for_examples = JSON.parse(
    File.read(File.expand_path('../../../../../examples/gameboy/import/import_report.json', __dir__))
  ).fetch('modules').map { |entry| entry.fetch('name') }.sort.freeze

  fixture_names_for_examples.each do |module_name|
    it "stages #{module_name} as Verilog semantically close to the original source", timeout: 240 do
      assert_staged_module_matches_source(module_name)
    end
  end

  it 'preserves keep-structure relative layout for source-backed components' do
    component_manifest.each do |component|
      rel = component['keep_structure_relative_path']
      next if rel.nil? || rel.empty?

      raised_path = component.fetch('raised_rhdl_path')
      expect(Pathname.new(raised_path).cleanpath.to_s).to end_with(rel.sub(/\.[^.]+\z/, '.rb'))
    end
  end
end
