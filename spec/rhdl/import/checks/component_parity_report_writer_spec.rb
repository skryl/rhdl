# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"
require "rhdl/import/checks/component_parity_report_writer"

RSpec.describe RHDL::Import::Checks::ComponentParityReportWriter do
  describe ".write" do
    it "writes component parity reports with normalized summary and mismatch fields" do
      Dir.mktmpdir do |dir|
        path = described_class.write(
          root_dir: dir,
          component: "decode",
          profile: "ao486_component_parity",
          summary: {
            cycles_compared: 12,
            signals_compared: 24,
            pass_count: 23,
            fail_count: 1
          },
          mismatches: [
            {
              cycle: 7,
              signal: "out_sig",
              original: 1,
              generated_verilog: 0,
              generated_ir: 1
            }
          ]
        )

        expect(path).to eq(File.join(dir, "decode_component_parity.json"))
        expect(File.exist?(path)).to be(true)

        parsed = JSON.parse(File.read(path))
        expect(parsed.fetch("component")).to eq("decode")
        expect(parsed.fetch("profile")).to eq("ao486_component_parity")
        expect(parsed.dig("summary", "fail_count")).to eq(1)
        mismatch = parsed.fetch("mismatches").first
        expect(mismatch.fetch("cycle")).to eq(7)
        expect(mismatch.fetch("signal")).to eq("out_sig")
        expect(mismatch.fetch("original")).to eq(1)
        expect(mismatch.fetch("generated_verilog")).to eq(0)
        expect(mismatch.fetch("generated_ir")).to eq(1)
      end
    end
  end
end
