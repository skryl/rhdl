# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"
require "rhdl/import/checks/report_writer"

RSpec.describe RHDL::Import::Checks::ReportWriter do
  describe ".write" do
    it "writes a per-top differential report under the provided root directory" do
      Dir.mktmpdir do |dir|
        root_dir = File.join(dir, "reports", "differential")

        path = described_class.write(
          root_dir: root_dir,
          top: "TopMain",
          summary: {
            cycles_compared: 2,
            signals_compared: 4,
            pass_count: 3,
            fail_count: 1
          },
          mismatches: [
            { cycle: 1, signal: "out", expected: 1, actual: 0 }
          ]
        )

        expect(path).to eq(File.join(root_dir, "topmain_differential.json"))

        parsed = JSON.parse(File.read(path))
        expect(parsed).to eq(
          "top" => "TopMain",
          "summary" => {
            "cycles_compared" => 2,
            "signals_compared" => 4,
            "pass_count" => 3,
            "fail_count" => 1
          },
          "mismatches" => [
            { "cycle" => 1, "signal" => "out", "expected" => 1, "actual" => 0 }
          ]
        )
      end
    end

    it "uses deterministic filenames for equivalent top names" do
      Dir.mktmpdir do |dir|
        root_dir = File.join(dir, "reports", "differential")

        first = described_class.write(root_dir: root_dir, top: "Top Core", summary: {}, mismatches: [])
        second = described_class.write(root_dir: root_dir, top: "top-core", summary: {}, mismatches: [])
        third = described_class.write(root_dir: root_dir, top: " top_core ", summary: {}, mismatches: [])

        expected = File.join(root_dir, "top_core_differential.json")
        expect(first).to eq(expected)
        expect(second).to eq(expected)
        expect(third).to eq(expected)
      end
    end

    it "writes mismatch payload in deterministic cycle and signal order" do
      Dir.mktmpdir do |dir|
        root_dir = File.join(dir, "reports", "differential")

        path = described_class.write(
          root_dir: root_dir,
          top: "core",
          summary: {},
          mismatches: [
            { cycle: 2, signal: "z", expected: 1, actual: 0 },
            { cycle: 0, signal: "b", expected: 1, actual: 0 },
            { cycle: 0, signal: "a", expected: 0, actual: 1 },
            { cycle: 2, signal: "a", expected: 0, actual: 1 }
          ]
        )

        parsed = JSON.parse(File.read(path))
        expect(parsed.fetch("mismatches")).to eq(
          [
            { "cycle" => 0, "signal" => "a", "expected" => 0, "actual" => 1 },
            { "cycle" => 0, "signal" => "b", "expected" => 1, "actual" => 0 },
            { "cycle" => 2, "signal" => "a", "expected" => 0, "actual" => 1 },
            { "cycle" => 2, "signal" => "z", "expected" => 1, "actual" => 0 }
          ]
        )
      end
    end
  end
end
