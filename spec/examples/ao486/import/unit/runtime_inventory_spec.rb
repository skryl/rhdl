# frozen_string_literal: true

require 'spec_helper'

require_relative 'coverage_manifest'

RSpec.describe AO486UnitSupport::RuntimeImportSession do
  include AO486UnitSupport::RuntimeImportRequirements

  it 'builds a source-backed inventory from the default ao486 emitted import tree', timeout: 480 do
    require_reference_tree!
    require_import_tool!

    session = described_class.current
    inventory = session.inventory_records

    aggregate_failures do
      expect(inventory.length).to eq(RHDL::Examples::AO486::Unit::COVERED_MODULE_COUNT)
      expect(session.inventory_by_source_relative_path.length).to eq(RHDL::Examples::AO486::Unit::COVERED_SOURCE_FILE_COUNT)
      expect(
        session.inventory_by_source_relative_path.transform_values { |records| records.map(&:module_name).sort }
      ).to eq(RHDL::Examples::AO486::Unit::COVERED_SOURCE_FILES)
    end

    ao486 = session.module_record('ao486')
    l1_icache = session.module_record('l1_icache')

    aggregate_failures 'record metadata' do
      expect(ao486.source_relative_path).to eq('ao486/ao486.v')
      expect(ao486.generated_ruby_relative_path).to eq('ao486/ao486.rb')
      expect(File.file?(ao486.source_path)).to be(true)
      expect(File.file?(ao486.staged_source_path)).to be(true)
      expect(File.file?(ao486.generated_ruby_path)).to be(true)
      expect(ao486.component_class.verilog_module_name).to eq('ao486')

      expect(l1_icache.source_relative_path).to eq('cache/l1_icache.v')
      expect(l1_icache.generated_ruby_relative_path).to eq('cache/l1_icache.rb')
      expect(File.file?(l1_icache.source_path)).to be(true)
      expect(File.file?(l1_icache.staged_source_path)).to be(true)
      expect(File.file?(l1_icache.generated_ruby_path)).to be(true)
      expect(l1_icache.component_class.verilog_module_name).to eq('l1_icache')
    end
  end
end
