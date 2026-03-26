# frozen_string_literal: true

require 'spec_helper'

require_relative 'coverage_manifest'

RSpec.describe RHDL::Examples::AO486::Unit do
  it 'locks the current AO486 CPU mirrored coverage baseline' do
    expect(described_class::COVERED_SOURCE_FILE_COUNT).to eq(47)
    expect(described_class::COVERED_MODULE_COUNT).to eq(47)
  end

  it 'keeps representative source groupings locked' do
    expect(described_class::COVERED_SOURCE_FILES.fetch('ao486/ao486.v')).to eq(%w[ao486])
    expect(described_class::COVERED_SOURCE_FILES.fetch('ao486/pipeline/pipeline.v')).to eq(%w[pipeline])
    expect(described_class::COVERED_SOURCE_FILES.fetch('cache/l1_icache.v')).to eq(%w[l1_icache])
  end

  it 'maps each covered source file to a mirrored spec file' do
    unit_root = File.expand_path(__dir__)

    described_class::COVERED_SOURCE_FILES.each do |source_relative_path, module_names|
      spec_path = File.join(unit_root, described_class.spec_relative_path_for(source_relative_path))
      expect(File.file?(spec_path)).to be(true), "Missing mirrored spec for #{source_relative_path}: #{spec_path}"
      expect(module_names).to eq(module_names.uniq.sort)
      expect(module_names).not_to be_empty
    end
  end
end
