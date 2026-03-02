# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

RSpec.describe "rhdl import command" do
  let(:project_root) { File.expand_path("../../..", __dir__) }
  let(:cli_path) { File.join(project_root, "exe/rhdl") }

  def run_cli(*args, env: {}, preload: nil)
    command = [RbConfig.ruby, "-Ilib"]
    command.concat(["-r", preload]) if preload
    command << cli_path
    command.concat(args)

    Open3.capture3(env, *command, chdir: project_root)
  end

  def write_import_project_stub(path)
    File.write(path, <<~RUBY)
      # frozen_string_literal: true

      require "json"
      require "fileutils"
      require "rhdl"

      module RHDL
        module Import
          class << self
            def project(**options)
              scenario = ENV.fetch("RHDL_IMPORT_SCENARIO", "success")
              out_dir = options[:out] || File.join(Dir.pwd, "tmp", "import_cli_stub")
              report_path = options[:report] || File.join(out_dir, "reports", "import_report.json")

              converted_modules = ["top_ok"]
              failed_modules = []
              checks = []

              case scenario
              when "partial"
                failed_modules = [
                  {
                    name: "top_bad",
                    code: "unsupported",
                    message: "unsupported construct"
                  }
                ]
              when "check_failure"
                checks = [
                  {
                    top: "top_ok",
                    status: "fail",
                    backend: "icarus",
                    summary: {
                      cycles_compared: 1,
                      signals_compared: 1,
                      pass_count: 0,
                      fail_count: 1
                    },
                    mismatches: [
                      {
                        cycle: 0,
                        signal: "in_a",
                        expected: 0,
                        actual: 1
                      }
                    ]
                  }
                ]
              end

              status = failed_modules.empty? && checks.none? { |entry| entry[:status].to_s == "fail" } ? :success : :failure
              report = Report.build(
                out: out_dir,
                options: options,
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

              status == :success ? Result.success(**payload) : Result.failure(**payload)
            end
          end
        end
      end
    RUBY
  end

  def run_cli_import_scenario(scenario, extra_args: [])
    Dir.mktmpdir do |dir|
      preload_path = File.join(dir, "import_project_stub.rb")
      report_path = File.join(dir, "import_report.json")
      source_dir = File.join(dir, "src")

      FileUtils.mkdir_p(source_dir)
      File.write(File.join(source_dir, "top_ok.sv"), "module top_ok; endmodule\n")
      write_import_project_stub(preload_path)

      stdout, stderr, status = run_cli(
        "import",
        "--src", source_dir,
        "--top", "top_ok",
        "--report", report_path,
        *Array(extra_args),
        env: { "RHDL_IMPORT_SCENARIO" => scenario },
        preload: preload_path
      )

      report = File.exist?(report_path) ? JSON.parse(File.read(report_path)) : nil
      [stdout, stderr, status, report]
    end
  end

  it "shows import in top-level help" do
    stdout, = run_cli("--help")

    expect(stdout).to include("import")
  end

  it "shows import help surface" do
    stdout, _stderr, status = run_cli("import", "--help")

    expect(status.success?).to be(true)
    expect(stdout).to include("Usage: rhdl import [options]")
    expect(stdout).to include("--filelist FILE")
    expect(stdout).to include("--src DIR")
    expect(stdout).to include("--dependency-resolution MODE")
    expect(stdout).to include("--compile-unit-filter MODE")
    expect(stdout).to include("--missing-modules MODE")
    expect(stdout).to include("--recovery-mode MODE")
    expect(stdout).to include("--hint-backend BACKEND")
    expect(stdout).to include("--hint-min-confidence LEVEL")
    expect(stdout).to include("--hint-conflict-policy POLICY")
    expect(stdout).to include("--check-profile PROFILE")
    expect(stdout).to include("--top MODULE")
    expect(stdout).to include("--check")
    expect(stdout).to include("--no-check")
    expect(stdout).to include("--check-backend BACKEND")
    expect(stdout).to include("--trace-cycles N")
    expect(stdout).to include("--trace-reference-root DIR")
    expect(stdout).to include("--trace-converted-export-mode MODE")
    expect(stdout).to include("--report FILE")
  end

  it "exits zero for a full-success import flow" do
    _stdout, _stderr, status, report = run_cli_import_scenario("success")

    expect(status.success?).to be(true)
    normalized_report = assert_import_report_skeleton!(report, status: :success)
    expect(normalized_report.dig("modules", "converted")).to include("top_ok")
    expect(normalized_report.dig("modules", "failed")).to eq([])
  end

  it "exits non-zero for partial conversion and preserves partial output in report" do
    _stdout, _stderr, status, report = run_cli_import_scenario("partial")

    expect(non_zero_import_exit?(status)).to be(true)
    normalized_report = assert_import_report_skeleton!(report, status: :failure)
    expect(normalized_report.dig("modules", "converted")).to include("top_ok")
    expect(normalized_report.dig("modules", "failed")).not_to be_empty
  end

  it "exits non-zero when checks fail after conversion" do
    _stdout, _stderr, status, report = run_cli_import_scenario("check_failure")

    expect(non_zero_import_exit?(status)).to be(true)
    normalized_report = assert_import_report_skeleton!(report, status: :failure)
    expect(normalized_report.dig("modules", "failed")).to eq([])
    expect(normalized_report.dig("summary", "checks_failed")).to eq(1)
    expect(normalized_report.fetch("checks").length).to eq(1)
    expect(normalized_report.dig("checks", 0, "status")).to eq("fail")
  end

  it "propagates --no-check as check=false into import options" do
    _stdout, _stderr, status, report = run_cli_import_scenario("success", extra_args: ["--no-check"])

    expect(status.success?).to be(true)
    normalized_report = assert_import_report_skeleton!(report, status: :success)
    expect(normalized_report.dig("project", "options", "check")).to eq(false)
  end

  it "propagates advanced importer options into import options" do
    _stdout, _stderr, status, report = run_cli_import_scenario(
      "success",
      extra_args: [
        "--dependency-resolution", "parent_root_auto_scan",
        "--compile-unit-filter", "modules_only",
        "--missing-modules", "blackbox_stubs",
        "--recovery-mode", "strict",
        "--hint-backend", "surelog",
        "--hint-min-confidence", "high",
        "--hint-conflict-policy", "prefer_hint",
        "--check-profile", "ao486_trace",
        "--trace-cycles", "256",
        "--trace-reference-root", "/tmp/ao486_ref",
        "--trace-converted-export-mode", "dsl_super"
      ]
    )

    expect(status.success?).to be(true)
    normalized_report = assert_import_report_skeleton!(report, status: :success)
    expect(normalized_report.dig("project", "options", "dependency_resolution")).to eq("parent_root_auto_scan")
    expect(normalized_report.dig("project", "options", "compile_unit_filter")).to eq("modules_only")
    expect(normalized_report.dig("project", "options", "missing_modules")).to eq("blackbox_stubs")
    expect(normalized_report.dig("project", "options", "recovery_mode")).to eq("strict")
    expect(normalized_report.dig("project", "options", "hint_backend")).to eq("surelog")
    expect(normalized_report.dig("project", "options", "hint_min_confidence")).to eq("high")
    expect(normalized_report.dig("project", "options", "hint_conflict_policy")).to eq("prefer_hint")
    expect(normalized_report.dig("project", "options", "check_profile")).to eq("ao486_trace")
    expect(normalized_report.dig("project", "options", "trace_cycles")).to eq(256)
    expect(normalized_report.dig("project", "options", "trace_reference_root")).to eq("/tmp/ao486_ref")
    expect(normalized_report.dig("project", "options", "trace_converted_export_mode")).to eq("dsl_super")
  end
end
