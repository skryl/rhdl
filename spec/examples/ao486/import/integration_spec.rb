# frozen_string_literal: true

require "json"
require "spec_helper"
require "set"
require "tmpdir"

RSpec.describe "ao486 importer integration", :slow do
  it "converts ao486 with blackbox stubs and writes a complete report" do
    source_root = File.expand_path("../../../../examples/ao486/reference/rtl/ao486", __dir__)
    skip "ao486 reference RTL is unavailable" unless Dir.exist?(source_root)

    Dir.mktmpdir do |dir|
      out_dir = File.join(dir, "ao486_import")
      result = RHDL::Import.project(
        out: out_dir,
        src: [source_root],
        dependency_resolution: "none",
        compile_unit_filter: "modules_only",
        missing_modules: "blackbox_stubs",
        no_check: true
      )

      expect(result).to be_success
      report = JSON.parse(File.read(result.report_path))
      normalized_report = assert_import_report_skeleton!(report, status: :success)
      summary = normalized_report.fetch("summary")

      expect(summary.fetch("converted_modules")).to be >= 40
      expect(summary.fetch("failed_modules")).to eq(0)
      expect(summary.fetch("blackboxes_generated")).to be >= 1
      expect(normalized_report.fetch("blackboxes_generated")).to include("cpu_export")
      expect(normalized_report.fetch("blackboxes_generated")).to include("l1_icache")

      module_files = Dir.glob(File.join(out_dir, "lib", "*", "modules", "**", "*.rb")).sort
      expect(module_files).not_to be_empty
      expected_module_files = (
        Array(normalized_report.dig("modules", "converted")) +
        Array(normalized_report.fetch("blackboxes_generated"))
      ).map { |name| "#{name.to_s.underscore}.rb" }.to_set
      actual_module_files = module_files.map { |path| File.basename(path) }.to_set
      expect(actual_module_files).to eq(expected_module_files)

      module_files.each do |module_file|
        source = File.read(module_file)
        expect(source).not_to match(/^\s*def\s+self\.to_verilog(?:_generated)?\b/)
        expect(source).not_to match(/^\s*def\s+self\.(sig|lit|mux|u)\b/)
        expect(source).not_to match(/\bRHDL::DSL::(?:SignalRef|Literal|TernaryOp|UnaryOp|BinaryOp|Concatenation|Replication)\b/)
      end
    end
  end
end
