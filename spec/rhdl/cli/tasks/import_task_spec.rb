# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "rhdl/cli"
require "rhdl/import/report"
require "rhdl/import/result"
require "stringio"
require "tmpdir"

RSpec.describe RHDL::CLI::Tasks::ImportTask do
  def capture_task_run(task)
    stdout_capture = StringIO.new
    stderr_capture = StringIO.new
    return_value = nil
    exit_code = nil

    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = stdout_capture
    $stderr = stderr_capture

    begin
      return_value = task.run
    rescue SystemExit => e
      exit_code = normalize_import_exit_code(e.status)
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end

    exit_code ||= infer_exit_code(return_value)

    {
      exit_code: exit_code,
      return_value: return_value,
      stdout: stdout_capture.string,
      stderr: stderr_capture.string
    }
  end

  def infer_exit_code(value)
    return value if value.is_a?(Integer)
    return 0 if value == true
    return 1 if value == false || value.nil?
    return value.success? ? 0 : 1 if value.respond_to?(:success?)

    0
  end

  def build_stub_result(status:, out_dir:, converted_modules:, failed_modules:, checks:)
    report_path = File.join(out_dir, "reports", "import_report.json")
    report = RHDL::Import::Report.build(
      out: out_dir,
      options: { src: ["/tmp/src"], top: ["top_ok"] },
      status: status,
      converted_modules: converted_modules,
      failed_modules: failed_modules,
      checks: checks
    )

    FileUtils.mkdir_p(File.dirname(report_path))
    File.write(report_path, JSON.pretty_generate(report))

    payload = {
      out_dir: out_dir,
      report_path: report_path,
      report: report,
      converted_modules: converted_modules,
      failed_modules: failed_modules
    }

    status == :success ? RHDL::Import::Result.success(**payload) : RHDL::Import::Result.failure(**payload)
  end

  describe "#run" do
    it "returns success semantics for a full-success import flow" do
      Dir.mktmpdir do |dir|
        result = build_stub_result(
          status: :success,
          out_dir: File.join(dir, "out"),
          converted_modules: ["top_ok"],
          failed_modules: [],
          checks: [{ top: "top_ok", status: "pass" }]
        )
        allow(RHDL::Import).to receive(:project).and_return(result)

        task = described_class.new(src: [dir], top: ["top_ok"])
        outcome = capture_task_run(task)

        expect(RHDL::Import).to have_received(:project)
        expect(outcome[:exit_code]).to eq(0)
        expect(result).to be_success
        normalized_report = assert_import_report_skeleton!(result.report, status: :success)
        expect(normalized_report.dig("modules", "converted")).to include("top_ok")
        expect(normalized_report.dig("modules", "failed")).to eq([])
      end
    end

    it "returns non-zero semantics when partial conversion fails some modules" do
      Dir.mktmpdir do |dir|
        result = build_stub_result(
          status: :failure,
          out_dir: File.join(dir, "out"),
          converted_modules: ["top_ok"],
          failed_modules: [
            { name: "top_bad", code: "unsupported", message: "unsupported construct" }
          ],
          checks: []
        )
        allow(RHDL::Import).to receive(:project).and_return(result)

        task = described_class.new(src: [dir], top: ["top_ok"])
        outcome = capture_task_run(task)

        expect(RHDL::Import).to have_received(:project)
        expect(non_zero_import_exit?(outcome[:exit_code])).to be(true)
        normalized_report = assert_import_report_skeleton!(result.report, status: :failure)
        expect(normalized_report.dig("modules", "converted")).to include("top_ok")
        expect(normalized_report.dig("modules", "failed")).not_to be_empty
      end
    end

    it "returns non-zero semantics when differential checks fail" do
      Dir.mktmpdir do |dir|
        result = build_stub_result(
          status: :failure,
          out_dir: File.join(dir, "out"),
          converted_modules: ["top_ok"],
          failed_modules: [],
          checks: [
            {
              top: "top_ok",
              status: "fail",
              backend: "icarus",
              summary: {
                cycles_compared: 1,
                signals_compared: 1,
                pass_count: 0,
                fail_count: 1
              }
            }
          ]
        )
        allow(RHDL::Import).to receive(:project).and_return(result)

        task = described_class.new(src: [dir], top: ["top_ok"], check: true)
        outcome = capture_task_run(task)

        expect(RHDL::Import).to have_received(:project)
        expect(non_zero_import_exit?(outcome[:exit_code])).to be(true)
        normalized_report = assert_import_report_skeleton!(result.report, status: :failure)
        expect(normalized_report.dig("modules", "failed")).to eq([])
        expect(normalized_report.dig("summary", "checks_failed")).to eq(1)
      end
    end
  end
end
