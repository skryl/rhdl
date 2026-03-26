# frozen_string_literal: true

require 'spec_helper'

require_relative 'support'

RSpec.describe 'GameBoy import component manifest', slow: true do
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

  it 'records a manifest entry for every raised imported component' do
    expect(component_manifest).not_to be_empty

    raised_files = Dir.glob(File.join(fixture[:result].output_dir, '**', '*.rb')).sort
    expect(component_manifest.length).to eq(raised_files.length)
  end

  it 'includes the required per-component metadata' do
    required_keys = %w[
      verilog_module_name
      ruby_class_name
      raised_rhdl_path
      staged_verilog_path
      staged_verilog_module_name
      origin_kind
    ]

    component_manifest.each do |component|
      expect(component.keys).to include(*required_keys)
    end
  end

  it 'uses unique staged module mappings for all components' do
    names = component_manifest.map { |component| component.fetch('verilog_module_name') }
    expect(names.uniq).to eq(names)
  end
end
