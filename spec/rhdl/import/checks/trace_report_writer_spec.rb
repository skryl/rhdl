# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"
require "rhdl/import/checks/trace_report_writer"

RSpec.describe RHDL::Import::Checks::TraceReportWriter do
  describe ".write" do
    it "writes a deterministic trace comparison artifact" do
      Dir.mktmpdir do |dir|
        path = described_class.write(
          root_dir: dir,
          top: "ao486",
          profile: "ao486_trace",
          summary: {
            events_compared: 10,
            pass_count: 9,
            fail_count: 1,
            first_mismatch: { index: 3, expected: { "pc" => "0x10" }, actual: { "pc" => "0x14" } }
          },
          mismatches: [
            { index: 3, expected: { "pc" => "0x10" }, actual: { "pc" => "0x14" } }
          ]
        )

        expect(path).to eq(File.join(dir, "ao486_trace.json"))
        parsed = JSON.parse(File.read(path))
        expect(parsed.fetch("top")).to eq("ao486")
        expect(parsed.fetch("profile")).to eq("ao486_trace")
        expect(parsed.dig("summary", "events_compared")).to eq(10)
        expect(parsed.dig("summary", "fail_count")).to eq(1)
        expect(parsed.dig("mismatches", 0, "index")).to eq(3)
      end
    end
  end
end
