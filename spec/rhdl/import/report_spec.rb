require "spec_helper"
require "json"
require "time"
require "tmpdir"

RSpec.describe RHDL::Import::Report do
  describe ".build" do
    it "returns the import report skeleton schema" do
      report = described_class.build(out: "/tmp/out", options: { src: "src" }, status: :success)

      expect(report).to include(
        :schema_version,
        :generated_at,
        :status,
        :project,
        :summary,
        :modules,
        :blackboxes_generated,
        :diagnostics,
        :checks
      )
      expect(report[:schema_version]).to eq(1)
      expect(report[:status]).to eq("success")
      expect(report[:project]).to include(:out_dir, :options, :tops)
      expect(report[:summary]).to eq(
        total_modules: 0,
        converted_modules: 0,
        failed_modules: 0,
        blackboxes_generated: 0,
        checks_run: 0,
        checks_failed: 0
      )
      expect(report[:modules]).to eq(converted: [], failed: [])
      expect(report[:blackboxes_generated]).to eq([])
      expect(report[:diagnostics]).to eq([])
      expect(report[:checks]).to eq([])
      expect { Time.iso8601(report[:generated_at]) }.not_to raise_error
    end

    it "counts failed checks in summary when check statuses are non-passing" do
      report = described_class.build(
        out: "/tmp/out",
        options: { src: "src" },
        status: :failure,
        checks: [
          { top: "top_ok", status: "pass" },
          { top: "top_skip", status: "skipped" },
          { top: "top_bad", status: "fail" },
          { top: "top_tool", status: "tool_failure" }
        ]
      )

      expect(report.dig(:summary, :checks_run)).to eq(4)
      expect(report.dig(:summary, :checks_failed)).to eq(2)
    end

    it "records generated blackbox stubs" do
      report = described_class.build(
        out: "/tmp/out",
        options: { src: "src" },
        status: :success,
        blackboxes_generated: %w[mem_prim pll_prim]
      )

      expect(report[:blackboxes_generated]).to eq(%w[mem_prim pll_prim])
      expect(report.dig(:summary, :blackboxes_generated)).to eq(2)
    end

    it "includes deterministic recovery and hint sections" do
      report = described_class.build(
        out: "/tmp/out",
        options: { src: "src", recovery_mode: "recoverable", hint_backend: "surelog" },
        status: :success
      )

      expect(report).to include(:recovery, :hints)
      expect(report.dig(:recovery, :summary)).to eq(
        preserved_count: 0,
        lowered_count: 0,
        nonrecoverable_count: 0,
        hint_applied_count: 0
      )
      expect(report.dig(:recovery, :events)).to eq([])
      expect(report.dig(:hints, :backend)).to eq("surelog")
      expect(report.dig(:hints, :available)).to eq(false)
      expect(report.dig(:hints, :applied_count)).to eq(0)
      expect(report.dig(:hints, :summary)).to eq(
        extracted_count: 0,
        applied_count: 0,
        discarded_count: 0,
        conflict_count: 0
      )
      expect(report.dig(:hints, :diagnostics)).to eq([])
    end
  end

  describe ".write" do
    it "persists JSON with the expected top-level skeleton keys" do
      Dir.mktmpdir do |dir|
        report = described_class.build(out: dir, options: { src: "src" }, status: :failure)
        path = described_class.write(report, out: dir)

        parsed = JSON.parse(File.read(path))
        expect(path).to eq(File.join(dir, "reports", "import_report.json"))
        expect(parsed.keys).to include(
          "schema_version",
          "generated_at",
          "status",
          "project",
          "summary",
          "modules",
          "blackboxes_generated",
          "diagnostics",
          "checks"
        )
        expect(parsed["status"]).to eq("failure")
      end
    end
  end
end
