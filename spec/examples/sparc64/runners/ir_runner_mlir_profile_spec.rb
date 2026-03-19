# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../support/sparc64/mlir_opt_matrix_support'

RSpec.describe 'SPARC64 to_mlir_hierarchy profiling', slow: true do
  let(:report_path) { File.expand_path('../../../../tmp/sparc64_ir_compiler_mlir_profile/report.json', __dir__) }
  let(:variant_report_path) { File.expand_path('../../../../tmp/sparc64_ir_compiler_mlir_profile_variant/report.json', __dir__) }
  let(:sample_seconds) { Integer(ENV.fetch('SPARC64_MLIR_PROFILE_SAMPLE_SECONDS', '60')) }

  it 'captures stackprof samples for the raw-core import -> raise -> to_mlir_hierarchy path', timeout: 3600 do
    skip 'stackprof not installed' unless Gem::Specification.find_all_by_name('stackprof').any?

    report = Sparc64MlirOptMatrixSupport.profile_to_mlir_hierarchy!(
      report_path: report_path,
      sample_seconds: sample_seconds
    )

    expect(report.fetch('import_circt_mlir_seconds')).to be >= 0.0
    expect(report.fetch('raise_circt_components_seconds')).to be >= 0.0
    expect(report.fetch('to_mlir_profiled_seconds')).to be >= 0.0
    expect(report.fetch('completed') || report.fetch('timed_out') || !report['export_error'].nil?).to be(true)
    expect(File.file?(report.fetch('stackprof_dump_path'))).to be(true)
    expect(report.fetch('top_frames')).not_to be_empty
    if report['stackprof_text_path']
      expect(File.file?(report.fetch('stackprof_text_path'))).to be(true)
    end
  end

  it 'captures stackprof samples for the first circt-opt variant before the downstream export', timeout: 3600 do
    skip 'stackprof not installed' unless Gem::Specification.find_all_by_name('stackprof').any?
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    report = Sparc64MlirOptMatrixSupport.profile_variant_to_mlir_hierarchy!(
      report_path: variant_report_path,
      variant_id: 'hw_flatten_modules_canonicalize_cse',
      sample_seconds: sample_seconds
    )

    expect(report.fetch('circt_verilog_command')).to include('--ir-hw')
    expect(report.fetch('import_circt_mlir_seconds')).to be >= 0.0
    expect(report.fetch('raise_circt_components_seconds')).to be >= 0.0
    expect(report.fetch('to_mlir_profiled_seconds')).to be >= 0.0
    expect(report.fetch('variant')).to include('id' => 'hw_flatten_modules_canonicalize_cse')
    expect(File.file?(report.fetch('variant').fetch('optimized_mlir_path'))).to be(true)
    expect(report.fetch('completed') || report.fetch('timed_out') || !report['export_error'].nil?).to be(true)
    expect(File.file?(report.fetch('stackprof_dump_path'))).to be(true)
    expect(report.fetch('top_frames')).not_to be_empty
    if report['stackprof_text_path']
      expect(File.file?(report.fetch('stackprof_text_path'))).to be(true)
    end
  end
end
