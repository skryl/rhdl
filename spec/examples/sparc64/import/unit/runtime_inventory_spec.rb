# frozen_string_literal: true

require 'spec_helper'

require_relative 'coverage_manifest'

RSpec.describe Sparc64UnitSupport::RuntimeImportSession do
  include Sparc64UnitSupport::RuntimeImportRequirements

  it 'builds a source-backed inventory from the default W1 emitted import tree', timeout: 480 do
    require_reference_tree!
    require_import_tool!

    session = described_class.current
    inventory = session.inventory_records

    aggregate_failures do
      expect(session.emitted_ruby_records.length).to eq(488)
      expect(inventory.length).to eq(RHDL::Examples::SPARC64::Unit::COVERED_MODULE_COUNT)
      expect(session.inventory_by_source_relative_path.length).to eq(RHDL::Examples::SPARC64::Unit::COVERED_SOURCE_FILE_COUNT)
      expect(
        session.inventory_by_source_relative_path.transform_values { |records| records.map(&:module_name).sort }
      ).to eq(RHDL::Examples::SPARC64::Unit::COVERED_SOURCE_FILES)
    end

    w1 = session.module_record('W1')
    dff_s = session.module_record('dff_s')

    aggregate_failures 'record metadata' do
      expect(w1.source_relative_path).to eq('Top/W1.v')
      expect(w1.generated_ruby_relative_path).to eq('Top/w1.rb')
      expect(w1.staged_source_path).to end_with('/mixed_sources/Top/W1.v')
      expect(File.file?(w1.source_path)).to be(true)
      expect(File.file?(w1.staged_source_path)).to be(true)
      expect(File.file?(w1.generated_ruby_path)).to be(true)
      expect(w1.component_class).to be(W1)
      expect(w1.component_class.verilog_module_name).to eq('W1')

      expect(dff_s.source_relative_path).to eq('T1-common/common/swrvr_clib.v')
      expect(dff_s.generated_ruby_relative_path).to eq('T1-common/common/dff_s.rb')
      expect(dff_s.staged_source_path).to end_with('/mixed_sources/T1-common/common/swrvr_clib.v')
      expect(File.file?(dff_s.source_path)).to be(true)
      expect(File.file?(dff_s.staged_source_path)).to be(true)
      expect(File.file?(dff_s.generated_ruby_path)).to be(true)
      expect(dff_s.component_class).to be(DffS)
      expect(dff_s.component_class.verilog_module_name).to eq('dff_s')
    end

    multi_module_source = session.modules_for_source('T1-FPU/fpu_rptr_min_global.v').map(&:module_name)
    partial_source = session.modules_for_source('T1-common/common/swrvr_clib.v').map(&:module_name)
    w1_dependencies = session.dependency_verilog_files_for_source('Top/W1.v')
    staged_w1_dependencies = session.staged_dependency_verilog_files_for_source('Top/W1.v')
    cmp_parity_dependencies = session.parity_dependency_verilog_files_for('cmp_sram_redhdr')

    aggregate_failures 'grouping by source file' do
      expect(multi_module_source).to eq(
        RHDL::Examples::SPARC64::Unit::COVERED_SOURCE_FILES.fetch('T1-FPU/fpu_rptr_min_global.v')
      )
      expect(partial_source).to eq(
        RHDL::Examples::SPARC64::Unit::COVERED_SOURCE_FILES.fetch('T1-common/common/swrvr_clib.v')
      )
    end

    aggregate_failures 'dependency and include metadata' do
      expect(session.include_dirs).to include(
        end_with('/examples/sparc64/reference/T1-common/include'),
        end_with('/examples/sparc64/reference/WB')
      )
      expect(session.staged_include_dirs).to include(
        end_with('/mixed_sources/T1-common/include'),
        end_with('/mixed_sources/WB')
      )
      expect(w1_dependencies).to include(
        end_with('/examples/sparc64/reference/Top/W1.v'),
        end_with('/examples/sparc64/reference/WB/wb_conbus_top.v')
      )
      expect(staged_w1_dependencies).to include(
        end_with('/mixed_sources/Top/W1.v'),
        end_with('/mixed_sources/WB/wb_conbus_top.v')
      )
      expect(cmp_parity_dependencies).to include(
        end_with('/examples/sparc64/reference/T1-common/common/cmp_sram_redhdr.v'),
        end_with('/examples/sparc64/reference/T1-common/u1/u1.V')
      )
    end
  end
end
