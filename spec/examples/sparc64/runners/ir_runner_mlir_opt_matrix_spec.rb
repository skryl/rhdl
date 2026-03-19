# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../support/sparc64/mlir_opt_matrix_support'
require_relative '../../../../examples/sparc64/utilities/integration/import_loader'

RSpec.describe 'SPARC64 IR compiler MLIR optimization matrix', slow: true do
  let(:report_path) { File.expand_path('../../../../tmp/sparc64_ir_compiler_mlir_opt_matrix/report.json', __dir__) }

  it 'runs circt-opt variants before measuring downstream RHDL import and hierarchy export sizes', timeout: 3600 do
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    report = Sparc64MlirOptMatrixSupport.build_report!(report_path: report_path)
    variant_ids = report.fetch('variants').map { |variant| variant.fetch('id') }
    successful = report.fetch('variants').select { |variant| variant['success'] }
    triple_opt = report.fetch('variants').find { |variant| variant.fetch('id') == 'hw_flatten_modules_canonicalize_cse' }

    expect(variant_ids.first).to eq('hw_flatten_modules_canonicalize_cse')
    expect(variant_ids).to include('hw_flatten_modules')
    expect(variant_ids).to include('circt_opt_passthrough')
    expect(successful).not_to be_empty
    expect(triple_opt).not_to be_nil
    expect(report.fetch('circt_verilog_command')).to include('--ir-hw')
    successful.each do |variant|
      expect(variant.fetch('import_circt_mlir_seconds')).to be >= 0.0
      expect(variant.fetch('raise_circt_components_seconds')).to be >= 0.0
      expect(variant.fetch('to_mlir_hierarchy_seconds')).to be >= 0.0
      expect(variant.fetch('exported_mlir_bytes')).to be > 0
      expect(File.file?(variant.fetch('exported_mlir_path'))).to be(true)
    end
    expect(report.dig('best_success_variant', 'id')).not_to be_nil
    expect(report.fetch('importer_run_seconds')).to be >= 0.0
    expect(report.fetch('input_mlir_bytes')).to be > 0
    expect(File.file?(report_path)).to be(true)
  end
end
