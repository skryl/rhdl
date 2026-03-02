require "spec_helper"

RSpec.describe RHDL::Import::Result do
  describe ".success" do
    it "builds a success result skeleton" do
      result = described_class.success(
        out_dir: "/tmp/out",
        report_path: "/tmp/out/reports/import_report.json"
      )

      expect(result).to be_success
      expect(result).not_to be_failure
      expect(result.status).to eq(:success)
      expect(result.out_dir).to eq("/tmp/out")
      expect(result.report_path).to eq("/tmp/out/reports/import_report.json")
      expect(result.errors).to eq([])
      expect(result.diagnostics).to eq([])
      expect(result.converted_modules).to eq([])
      expect(result.failed_modules).to eq([])
    end
  end

  describe ".failure" do
    it "builds a failure result skeleton" do
      result = described_class.failure(
        out_dir: "/tmp/out",
        report_path: "/tmp/out/reports/import_report.json",
        errors: ["frontend failed"],
        diagnostics: [{ code: "tool_failure", message: "verilator failed" }]
      )

      expect(result).to be_failure
      expect(result).not_to be_success
      expect(result.status).to eq(:failure)
      expect(result.errors).to eq(["frontend failed"])
      expect(result.diagnostics).to eq([{ code: "tool_failure", message: "verilator failed" }])
      expect(result.converted_modules).to eq([])
      expect(result.failed_modules).to eq([])
    end
  end
end
