# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::Examples::SPARC64::Unit::SourceFileDriver do
  describe '.staged_verilog_report_for' do
    let(:session) do
      instance_double(
        Sparc64UnitSupport::RuntimeImportSession,
        temp_root: '/tmp/sparc64_runtime',
        dependency_verilog_files_for_source: original_dependencies,
        staged_dependency_verilog_files_for_source: staged_dependencies,
        include_dirs: ['/reference/include', '/reference/WB'],
        staged_include_dirs: ['/staged/include', '/staged/WB']
      )
    end

    let(:source_relative_path) { 'Top/W1.v' }
    let(:source_path) { '/reference/Top/W1.v' }
    let(:staged_source_path) { '/staged/Top/W1.v' }
    let(:original_dependencies) { ['/reference/WB/wb_conbus_top.v', source_path] }
    let(:staged_dependencies) { ['/staged/WB/wb_conbus_top.v', staged_source_path] }
    let(:expected_original_paths) { [source_path, '/reference/WB/wb_conbus_top.v'] }
    let(:expected_staged_paths) { [staged_source_path, '/staged/WB/wb_conbus_top.v'] }

    before do
      described_class.source_report_cache.clear
    end

    it 'compares the staged dependency closure and includes import include dirs for single-module sources' do
      base_dir = described_class.semantic_base_dir_for(session: session, source_relative_path: source_relative_path)

      expect(Sparc64ParityHelper).to receive(:staged_verilog_semantic_report).with(
        original_paths: expected_original_paths,
        staged_paths: expected_staged_paths,
        base_dir: base_dir,
        module_names: %w[W1],
        original_include_dirs: ['/reference/include', '/reference/WB'],
        staged_include_dirs: ['/staged/include', '/staged/WB'],
        top_module: 'W1'
      ).and_return(match: true)

      report = described_class.staged_verilog_report_for(
        session: session,
        source_relative_path: source_relative_path,
        source_path: source_path,
        staged_source_path: staged_source_path,
        module_names: %w[W1]
      )

      expect(report).to eq(match: true)
    end

    it 'does not force a top module for multi-module source files' do
      expected_multi_original_paths = [
        '/reference/T1-common/common/swrvr_clib.v',
        '/reference/WB/wb_conbus_top.v',
        '/reference/Top/W1.v'
      ]
      expected_multi_staged_paths = [
        '/staged/T1-common/common/swrvr_clib.v',
        '/staged/WB/wb_conbus_top.v',
        '/staged/Top/W1.v'
      ]

      expect(Sparc64ParityHelper).to receive(:staged_verilog_semantic_report).with(
        hash_including(
          original_paths: expected_multi_original_paths,
          staged_paths: expected_multi_staged_paths,
          module_names: %w[dff_s mux2ds],
          top_module: nil
        )
      ).and_return(match: true)

      described_class.staged_verilog_report_for(
        session: session,
        source_relative_path: 'T1-common/common/swrvr_clib.v',
        source_path: '/reference/T1-common/common/swrvr_clib.v',
        staged_source_path: '/staged/T1-common/common/swrvr_clib.v',
        module_names: %w[dff_s mux2ds]
      )
    end
  end
end
