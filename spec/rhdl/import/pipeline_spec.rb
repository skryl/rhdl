# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"
require "rhdl/import/pipeline"

RSpec.describe RHDL::Import::Pipeline do
  describe ".run" do
    it "writes partial output and returns failure when conversion failures exist" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: { src: ["/tmp/src"], top: [] },
          translated_modules: [
            { name: "top_ok", dependencies: ["leaf"], ruby_source: "class TopOk; end\n" },
            { name: "leaf", dependencies: [], ruby_source: "class Leaf; end\n" },
            { name: "top_bad", dependencies: ["bad_dep"], ruby_source: "class TopBad; end\n" }
          ],
          failed_modules: [
            { name: "bad_dep", code: "unsupported", message: "unsupported construct" }
          ],
          diagnostics: [
            { code: "unsupported", module: "bad_dep", message: "unsupported construct" }
          ]
        )

        expect(result).to be_failure
        expect(result.converted_modules).to eq(%w[leaf top_ok])
        expect(result.failed_modules).to eq(
          [
            { name: "bad_dep", code: "unsupported", message: "unsupported construct" },
            {
              name: "top_bad",
              code: "failed_dependency",
              message: "depends on failed modules: bad_dep",
              failed_dependencies: ["bad_dep"]
            }
          ]
        )

        module_root = File.join(out, "lib", "demo_import", "modules")
        expect(File.exist?(File.join(module_root, "leaf.rb"))).to be(true)
        expect(File.exist?(File.join(module_root, "top_ok.rb"))).to be(true)
        expect(File.exist?(File.join(module_root, "top_bad.rb"))).to be(false)

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("failure")
        expect(report.dig("project", "tops")).to eq(%w[top_bad top_ok])
        expect(report.dig("modules", "converted")).to eq(%w[leaf top_ok])
        expect(report.dig("modules", "failed")).to eq(
          [
            { "name" => "bad_dep", "code" => "unsupported", "message" => "unsupported construct" },
            {
              "name" => "top_bad",
              "code" => "failed_dependency",
              "message" => "depends on failed modules: bad_dep",
              "failed_dependencies" => ["bad_dep"]
            }
          ]
        )
      end
    end

    it "preserves source-tree relative module output paths when source paths are provided" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        rtl_root = File.join(dir, "rtl")
        top_source = File.join(rtl_root, "pipeline", "top.v")
        leaf_source = File.join(rtl_root, "memory", "leaf.v")
        FileUtils.mkdir_p(File.dirname(top_source))
        FileUtils.mkdir_p(File.dirname(leaf_source))
        File.write(top_source, "module top; endmodule\n")
        File.write(leaf_source, "module leaf; endmodule\n")

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [rtl_root],
            source_files: [top_source, leaf_source],
            source_roots: [rtl_root],
            top: ["top"],
            no_check: true
          },
          translated_modules: [
            {
              name: "top",
              source_path: top_source,
              dependencies: ["leaf"],
              ruby_source: "class Top; end\n"
            },
            {
              name: "leaf",
              source_path: leaf_source,
              dependencies: [],
              ruby_source: "class Leaf; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_success
        expect(File.exist?(File.join(out, "lib", "demo_import", "modules", "pipeline", "top.rb"))).to be(true)
        expect(File.exist?(File.join(out, "lib", "demo_import", "modules", "memory", "leaf.rb"))).to be(true)
        expect(File.exist?(File.join(out, "lib", "demo_import", "modules", "top.rb"))).to be(false)
        expect(File.exist?(File.join(out, "lib", "demo_import", "modules", "leaf.rb"))).to be(false)
      end
    end

    it "writes recovery and hint metadata into import report" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: ["/tmp/src"],
            top: ["top"],
            no_check: true,
            recovery: {
              summary: {
                preserved_count: 2,
                lowered_count: 1,
                nonrecoverable_count: 0,
                hint_applied_count: 1
              },
              events: [
                { module: "top", construct: "case", status: "preserved" }
              ]
            },
            hints: {
              backend: "surelog",
              available: true,
              applied_count: 1,
              diagnostics: []
            }
          },
          translated_modules: [
            { name: "top", dependencies: [], ruby_source: "class Top; end\n" }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_success
        report = JSON.parse(File.read(result.report_path))
        expect(report.dig("recovery", "summary", "preserved_count")).to eq(2)
        expect(report.dig("recovery", "summary", "lowered_count")).to eq(1)
        expect(report.dig("recovery", "events")).to eq(
          [
            { "module" => "top", "construct" => "case", "status" => "preserved" }
          ]
        )
        expect(report.dig("hints", "backend")).to eq("surelog")
        expect(report.dig("hints", "available")).to eq(true)
        expect(report.dig("hints", "applied_count")).to eq(1)
      end
    end

    it "fails modules that define custom verilog export methods and prunes dependents" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: { src: ["/tmp/src"], top: ["top"], no_check: true },
          translated_modules: [
            {
              name: "dep",
              ruby_source: <<~RUBY
                class Dep < RHDL::Component
                  def self.to_verilog(top_name: nil)
                    "module dep; endmodule\\n"
                  end
                end
              RUBY
            },
            {
              name: "top",
              dependencies: ["dep"],
              ruby_source: "class Top; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_failure
        failure_index = result.failed_modules.each_with_object({}) { |entry, memo| memo[entry[:name]] = entry }
        expect(failure_index.fetch("dep")[:code]).to eq("forbidden_custom_verilog_export")
        expect(failure_index.fetch("dep")[:message]).to include("to_verilog")
        expect(failure_index.fetch("top")[:code]).to eq("failed_dependency")

        module_root = File.join(out, "lib", "demo_import", "modules")
        expect(File.exist?(File.join(module_root, "dep.rb"))).to be(false)
        expect(File.exist?(File.join(module_root, "top.rb"))).to be(false)

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("failure")
        failed_names = report.dig("modules", "failed").map { |entry| entry["name"] }
        expect(failed_names).to include("dep", "top")
      end
    end

    it "generates deterministic blackbox stubs for unresolved modules when policy is blackbox_stubs" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            top: ["top"],
            missing_modules: "blackbox_stubs",
            no_check: true
          },
          translated_modules: [
            {
              name: "top",
              ruby_source: "class Top; end\n",
              instances: [
                {
                  name: "u_leaf",
                  module_name: "leaf",
                  connections: [
                    { port: "clk" },
                    { port: "rst" }
                  ]
                },
                {
                  name: "u_mem",
                  module_name: "ext_mem",
                  parameter_overrides: [{ name: "WIDTH", value: 32 }],
                  connections: [
                    { port: "addr" },
                    { port: "data_o" }
                  ]
                }
              ]
            },
            {
              name: "leaf",
              ruby_source: "class Leaf; end\n",
              instances: []
            }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_success
        expect(result.converted_modules).to eq(%w[leaf top])
        expect(result.failed_modules).to eq([])

        module_root = File.join(out, "lib", "demo_import", "modules")
        expect(File.exist?(File.join(module_root, "leaf.rb"))).to be(true)
        expect(File.exist?(File.join(module_root, "top.rb"))).to be(true)
        stub_path = File.join(module_root, "ext_mem.rb")
        expect(File.exist?(stub_path)).to be(true)
        stub_source = File.read(stub_path)
        expect(stub_source).to include("# generated_blackbox_stub: true")
        expect(stub_source).to include("generic :WIDTH, default: 0")
        expect(stub_source).to include("input :addr")
        expect(stub_source).to include("input :data_o")
        expect(stub_source).not_to include("def self.to_verilog")

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("success")
        expect(report.fetch("blackboxes_generated")).to eq(["ext_mem"])
        expect(report.dig("summary", "blackboxes_generated")).to eq(1)
      end
    end

    it "infers blackbox signatures from source files when instance metadata lacks connections" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        source_file = File.join(dir, "top.v")
        File.write(
          source_file,
          <<~VERILOG
            module top;
              ext_mem #(
                .WIDTH(32),
                .DEPTH(1024)
              ) u_ext_mem (
                .clk(clk),
                .addr(addr),
                .data_o(data_o)
              );
            endmodule
          VERILOG
        )

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            source_files: [source_file],
            top: ["top"],
            missing_modules: "blackbox_stubs",
            no_check: true
          },
          translated_modules: [
            {
              name: "top",
              ruby_source: "class Top; end\n",
              instances: [
                {
                  name: "u_ext_mem",
                  module_name: "ext_mem",
                  parameter_overrides: [],
                  connections: []
                }
              ]
            }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_success
        stub_path = File.join(out, "lib", "demo_import", "modules", "ext_mem.rb")
        stub_source = File.read(stub_path)
        expect(stub_source).to include("generic :DEPTH, default: 0")
        expect(stub_source).to include("generic :WIDTH, default: 0")
        expect(stub_source).to include("input :addr")
        expect(stub_source).to include("input :clk")
        expect(stub_source).to include("input :data_o")
      end
    end

    it "fails on unresolved module dependencies when policy is fail" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            top: ["top"],
            missing_modules: "fail",
            no_check: true
          },
          translated_modules: [
            {
              name: "top",
              ruby_source: "class Top; end\n",
              instances: [
                { name: "u_leaf", module_name: "leaf" },
                { name: "u_mem", module_name: "ext_mem" }
              ]
            },
            {
              name: "leaf",
              ruby_source: "class Leaf; end\n",
              instances: []
            }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_failure
        expect(result.converted_modules).to eq(["leaf"])
        expect(result.failed_modules).to eq(
          [
            {
              name: "ext_mem",
              code: "missing_module",
              message: "unresolved dependency module \"ext_mem\", referenced by: top",
              referenced_by: ["top"]
            },
            {
              name: "top",
              code: "failed_dependency",
              message: "depends on failed modules: ext_mem",
              failed_dependencies: ["ext_mem"]
            }
          ]
        )

        module_root = File.join(out, "lib", "demo_import", "modules")
        expect(File.exist?(File.join(module_root, "leaf.rb"))).to be(true)
        expect(File.exist?(File.join(module_root, "top.rb"))).to be(false)
        expect(File.exist?(File.join(module_root, "ext_mem.rb"))).to be(false)

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("failure")
        expect(report.fetch("blackboxes_generated")).to eq([])
        expect(report.dig("summary", "blackboxes_generated")).to eq(0)
      end
    end

    it "fails when differential checks report mismatches" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        source_file = File.join(dir, "top_ok.sv")
        File.write(source_file, "module top_ok; endmodule\n")

        check_runner = lambda do |work_dir:, icarus_command:, verilator_command:, env:|
          expect(File.expand_path(work_dir)).to include(File.join("tmp", "checks", "top_ok"))
          expect(icarus_command.first).to eq("iverilog")
          expect(verilator_command.first).to eq("verilator")
          expect(env).to eq({})

          {
            status: :ok,
            selected_backend: :icarus,
            selected_command: {
              argv: icarus_command,
              shell: "iverilog -g2012 -s top_ok",
              stdout: "",
              stderr: "",
              exit_code: 0,
              chdir: work_dir,
              env: env
            },
            attempts: [
              {
                backend: :icarus,
                status: :ok,
                available: true,
                exit_code: 0,
                shell: "iverilog -g2012 -s top_ok",
                error_class: nil,
                error_message: nil
              }
            ]
          }
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            source_files: [source_file],
            expected_waveforms: { "top_ok" => { 0 => { "in_a" => 0 } } },
            actual_waveforms: { "top_ok" => { 0 => { "in_a" => 1 } } }
          },
          translated_modules: [
            {
              name: "top_ok",
              dependencies: [],
              ports: [{ name: "in_a", direction: "input", width: 1 }],
              ruby_source: "class TopOk; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: [],
          check_runner: check_runner
        )

        expect(result).to be_failure

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("failure")
        expect(report.dig("summary", "checks_run")).to eq(1)
        expect(report.dig("summary", "checks_failed")).to eq(1)
        expect(report.fetch("checks").length).to eq(1)
        expect(report.dig("checks", 0, "top")).to eq("top_ok")
        expect(report.dig("checks", 0, "status")).to eq("fail")
        expect(report.dig("checks", 0, "backend")).to eq("icarus")
        expect(File.exist?(report.dig("checks", 0, "report_path"))).to be(true)
      end
    end

    it "skips checks when no_check is enabled" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        source_file = File.join(dir, "top_ok.sv")
        File.write(source_file, "module top_ok; endmodule\n")

        check_runner = lambda do |_work_dir:, _icarus_command:, _verilator_command:, _env:|
          raise "check runner should not be called when no_check is true"
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            source_files: [source_file],
            no_check: true
          },
          translated_modules: [
            {
              name: "top_ok",
              dependencies: [],
              ports: [{ name: "in_a", direction: "input", width: 1 }],
              ruby_source: "class TopOk; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: [],
          check_runner: check_runner
        )

        expect(result).to be_success

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("success")
        expect(report.dig("summary", "checks_run")).to eq(0)
        expect(report.dig("summary", "checks_failed")).to eq(0)
        expect(report.fetch("checks")).to eq([])
      end
    end

    it "runs default checks only for converted detected tops" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        source_file = File.join(dir, "top_ok.sv")
        File.write(source_file, "module top_ok; endmodule\n")

        check_calls = []
        check_runner = lambda do |work_dir:, icarus_command:, verilator_command:, env:|
          check_calls << {
            work_dir: work_dir,
            icarus_command: icarus_command,
            verilator_command: verilator_command,
            env: env
          }
          {
            status: :ok,
            selected_backend: :icarus,
            selected_command: {
              argv: icarus_command,
              shell: "iverilog -g2012 -s top_ok",
              stdout: "",
              stderr: "",
              exit_code: 0,
              chdir: work_dir,
              env: env
            },
            attempts: []
          }
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            source_files: [source_file],
            expected_waveforms: { "top_ok" => { 0 => { "in_a" => 1 } } },
            actual_waveforms: { "top_ok" => { 0 => { "in_a" => 1 } } }
          },
          translated_modules: [
            {
              name: "top_ok",
              dependencies: [],
              ports: [{ name: "in_a", direction: "input", width: 1 }],
              ruby_source: "class TopOk; end\n"
            }
          ],
          failed_modules: [
            { name: "top_failed", code: "unsupported", message: "unsupported construct" }
          ],
          diagnostics: [],
          check_runner: check_runner
        )

        expect(result).to be_failure
        expect(check_calls.length).to eq(1)
        expect(check_calls.first[:icarus_command]).to include("-s", "top_ok")

        report = JSON.parse(File.read(result.report_path))
        expect(report.dig("summary", "checks_run")).to eq(1)
        expect(report.fetch("checks").map { |entry| entry.fetch("top") }).to eq(["top_ok"])
      end
    end

    it "runs ao486_trace profile checks using trace events" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")

        check_runner = lambda do |_work_dir:, _icarus_command:, _verilator_command:, _env:|
          raise "check runner should not be used for ao486_trace profile"
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace",
            expected_trace_events: {
              "top_ok" => [
                { "pc" => "0x1000", "eax" => 1 },
                { "pc" => "0x1004", "eax" => 2 }
              ]
            },
            actual_trace_events: {
              "top_ok" => [
                { "pc" => "0x1000", "eax" => 1 },
                { "pc" => "0x1004", "eax" => 3 }
              ]
            }
          },
          translated_modules: [
            {
              name: "top_ok",
              dependencies: [],
              ports: [{ name: "in_a", direction: "input", width: 1 }],
              ruby_source: "class TopOk; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: [],
          check_runner: check_runner
        )

        expect(result).to be_failure

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("failure")
        expect(report.dig("summary", "checks_run")).to eq(1)
        expect(report.dig("summary", "checks_failed")).to eq(1)
        expect(report.dig("checks", 0, "profile")).to eq("ao486_trace")
        expect(report.dig("checks", 0, "status")).to eq("fail")
        expect(report.dig("checks", 0, "summary", "events_compared")).to eq(2)
        expect(File.exist?(report.dig("checks", 0, "report_path"))).to be(true)
      end
    end

    it "prunes stale managed report artifacts from prior runs" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        stale_trace = File.join(out, "reports", "trace", "stale_trace.json")
        stale_program = File.join(out, "reports", "program_parity", "stale_program.json")
        FileUtils.mkdir_p(File.dirname(stale_trace))
        FileUtils.mkdir_p(File.dirname(stale_program))
        File.write(stale_trace, "{}\n")
        File.write(stale_program, "{}\n")

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace",
            expected_trace_events: { "top_ok" => [{ "pc" => "0x1000" }] },
            actual_trace_events: { "top_ok" => [{ "pc" => "0x1000" }] }
          },
          translated_modules: [
            {
              name: "top_ok",
              dependencies: [],
              ports: [],
              ruby_source: "class TopOk; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_success
        report = JSON.parse(File.read(result.report_path))
        current_trace_report = report.dig("checks", 0, "report_path")
        expect(File.exist?(current_trace_report)).to be(true)
        expect(File.exist?(stale_trace)).to be(false)
        expect(File.exist?(stale_program)).to be(false)
      end
    end

    it "loads ao486_trace events from JSON file paths" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        expected_path = File.join(dir, "expected_trace.json")
        actual_path = File.join(dir, "actual_trace.json")
        File.write(expected_path, JSON.pretty_generate({ "top_ok" => [{ "pc" => "0x1000" }] }))
        File.write(actual_path, JSON.pretty_generate({ "top_ok" => [{ "pc" => "0x1000" }] }))

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace",
            expected_trace_path: expected_path,
            actual_trace_path: actual_path
          },
          translated_modules: [
            {
              name: "top_ok",
              dependencies: [],
              ports: [{ name: "in_a", direction: "input", width: 1 }],
              ruby_source: "class TopOk; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_success
        report = JSON.parse(File.read(result.report_path))
        expect(report.dig("checks", 0, "profile")).to eq("ao486_trace")
        expect(report.dig("checks", 0, "status")).to eq("pass")
      end
    end

    it "loads ao486_trace events from command outputs" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        expected_cmd = ["ruby", "-rjson", "-e", 'print({"top_ok"=>[{"pc"=>"0x1000"}]}.to_json)']
        actual_cmd = ["ruby", "-rjson", "-e", 'print({"top_ok"=>[{"pc"=>"0x1000"}]}.to_json)']

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace",
            expected_trace_command: expected_cmd,
            actual_trace_command: actual_cmd
          },
          translated_modules: [
            {
              name: "top_ok",
              dependencies: [],
              ports: [{ name: "in_a", direction: "input", width: 1 }],
              ruby_source: "class TopOk; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_success
        report = JSON.parse(File.read(result.report_path))
        expect(report.dig("checks", 0, "profile")).to eq("ao486_trace")
        expect(report.dig("checks", 0, "status")).to eq("pass")
      end
    end

    it "loads ao486_trace events from built-in ao486 harness when no trace input is provided" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        harness_calls = []
        harness = lambda do |mode:, top:, out:, cycles:, source_root:, converted_export_mode:, cwd:|
          harness_calls << {
            mode: mode,
            top: top,
            out: out,
            cycles: cycles,
            source_root: source_root,
            converted_export_mode: converted_export_mode,
            cwd: cwd
          }
          { "ao486" => [{ "kind" => "sample", "cycle" => 0, "pc" => "0x1000" }] }
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace"
          },
          translated_modules: [
            {
              name: "ao486",
              dependencies: [],
              ports: [],
              ruby_source: "class Ao486; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: [],
          ao486_trace_harness: harness
        )

        expect(result).to be_success
        expect(harness_calls.length).to eq(2)
        expect(harness_calls.map { |entry| entry[:mode] }).to eq(%w[reference converted])
        expect(harness_calls.map { |entry| entry[:top] }).to all(eq("ao486"))
        expect(harness_calls.map { |entry| entry[:cycles] }).to all(eq(1024))

        report = JSON.parse(File.read(result.report_path))
        expect(report.dig("checks", 0, "status")).to eq("pass")
        expect(report.dig("checks", 0, "trace_sources", "expected", "type")).to eq("ao486_harness")
        expect(report.dig("checks", 0, "trace_sources", "actual", "type")).to eq("ao486_harness")
      end
    end

    it "routes ao486_trace_ir expected/actual harness modes to reference/converted_ir" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        harness_calls = []
        harness = lambda do |mode:, top:, out:, cycles:, source_root:, converted_export_mode:, cwd:|
          harness_calls << {
            mode: mode,
            top: top,
            out: out,
            cycles: cycles,
            source_root: source_root,
            converted_export_mode: converted_export_mode,
            cwd: cwd
          }
          { "ao486" => [{ "kind" => "sample", "cycle" => 0, "pc" => "0x1000" }] }
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace_ir"
          },
          translated_modules: [
            {
              name: "ao486",
              dependencies: [],
              ports: [],
              ruby_source: "class Ao486; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: [],
          ao486_trace_harness: harness
        )

        expect(result).to be_success
        expect(harness_calls.length).to eq(2)
        expect(harness_calls.map { |entry| entry[:mode] }).to eq(%w[reference converted_ir])

        report = JSON.parse(File.read(result.report_path))
        expect(report.dig("checks", 0, "profile")).to eq("ao486_trace_ir")
        expect(report.dig("checks", 0, "status")).to eq("pass")
      end
    end

    it "forwards trace harness options for ao486 built-in trace capture" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        calls = []
        harness = lambda do |mode:, top:, out:, cycles:, source_root:, converted_export_mode:, cwd:|
          calls << {
            mode: mode,
            top: top,
            out: out,
            cycles: cycles,
            source_root: source_root,
            converted_export_mode: converted_export_mode,
            cwd: cwd
          }
          { "ao486" => [{ "kind" => "sample", "cycle" => 0 }] }
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace",
            trace_cycles: 64,
            trace_reference_root: "/tmp/ao486_ref",
            trace_converted_export_mode: "dsl_super"
          },
          translated_modules: [
            {
              name: "ao486",
              dependencies: [],
              ports: [],
              ruby_source: "class Ao486; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: [],
          ao486_trace_harness: harness
        )

        expect(result).to be_success
        expect(calls.length).to eq(2)
        expect(calls.map { |entry| entry[:cycles] }).to all(eq(64))
        expect(calls.map { |entry| entry[:source_root] }).to all(eq("/tmp/ao486_ref"))
        expect(calls.map { |entry| entry[:converted_export_mode] }).to all(eq("dsl_super"))
      end
    end

    it "uses ao486 harness only for the missing trace side when one side is provided explicitly" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        harness_calls = []
        harness = lambda do |mode:, top:, out:, cycles:, source_root:, converted_export_mode:, cwd:|
          harness_calls << {
            mode: mode,
            top: top,
            out: out,
            cycles: cycles,
            source_root: source_root,
            converted_export_mode: converted_export_mode,
            cwd: cwd
          }
          { "ao486" => [{ "kind" => "sample", "cycle" => 0, "pc" => "0x1000" }] }
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace",
            expected_trace_events: {
              "ao486" => [{ "kind" => "sample", "cycle" => 0, "pc" => "0x1000" }]
            }
          },
          translated_modules: [
            {
              name: "ao486",
              dependencies: [],
              ports: [],
              ruby_source: "class Ao486; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: [],
          ao486_trace_harness: harness
        )

        expect(result).to be_success
        expect(harness_calls.length).to eq(1)
        expect(harness_calls.first[:mode]).to eq("converted")

        report = JSON.parse(File.read(result.report_path))
        expect(report.dig("checks", 0, "status")).to eq("pass")
        expect(report.dig("checks", 0, "trace_sources", "expected", "type")).to eq("inline")
        expect(report.dig("checks", 0, "trace_sources", "actual", "type")).to eq("ao486_harness")
      end
    end

    it "reports ao486 harness failures as tool_failure checks" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        harness = lambda do |**_kwargs|
          raise "ao486 harness boom"
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace"
          },
          translated_modules: [
            {
              name: "ao486",
              dependencies: [],
              ports: [],
              ruby_source: "class Ao486; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: [],
          ao486_trace_harness: harness
        )

        expect(result).to be_failure
        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("failure")
        expect(report.dig("checks", 0, "status")).to eq("tool_failure")
        expect(report.dig("checks", 0, "reason")).to eq("trace_input_error")
        expect(report.dig("checks", 0, "message")).to include("ao486 harness")
      end
    end

    it "applies trace key filtering for ao486_trace profile checks" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace",
            trace_keys: ["pc"],
            expected_trace_events: {
              "top_ok" => [{ "pc" => "0x1000", "eax" => 1 }]
            },
            actual_trace_events: {
              "top_ok" => [{ "pc" => "0x1000", "eax" => 9 }]
            }
          },
          translated_modules: [
            {
              name: "top_ok",
              dependencies: [],
              ports: [{ name: "in_a", direction: "input", width: 1 }],
              ruby_source: "class TopOk; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_success
        report = JSON.parse(File.read(result.report_path))
        expect(report.dig("checks", 0, "status")).to eq("pass")
        expect(report.dig("checks", 0, "summary", "keys")).to eq(["pc"])
      end
    end

    it "reports ao486_trace input errors as tool_failure checks" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        missing_path = File.join(dir, "missing_trace.json")

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace",
            expected_trace_path: missing_path
          },
          translated_modules: [
            {
              name: "top_ok",
              dependencies: [],
              ports: [{ name: "in_a", direction: "input", width: 1 }],
              ruby_source: "class TopOk; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_failure
        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("failure")
        expect(report.dig("summary", "checks_run")).to eq(1)
        expect(report.dig("summary", "checks_failed")).to eq(1)
        expect(report.dig("checks", 0, "profile")).to eq("ao486_trace")
        expect(report.dig("checks", 0, "status")).to eq("tool_failure")
        expect(report.dig("checks", 0, "reason")).to eq("trace_input_error")
      end
    end

    it "reports ao486_trace command failures as tool_failure checks" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        failing_cmd = ["ruby", "-e", "STDERR.puts('trace boom'); exit 3"]

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace",
            expected_trace_command: failing_cmd
          },
          translated_modules: [
            {
              name: "top_ok",
              dependencies: [],
              ports: [{ name: "in_a", direction: "input", width: 1 }],
              ruby_source: "class TopOk; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_failure
        report = JSON.parse(File.read(result.report_path))
        expect(report.dig("checks", 0, "profile")).to eq("ao486_trace")
        expect(report.dig("checks", 0, "status")).to eq("tool_failure")
        expect(report.dig("checks", 0, "reason")).to eq("trace_input_error")
      end
    end

    it "skips ao486_trace checks when no trace events are provided" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace"
          },
          translated_modules: [
            {
              name: "top_ok",
              dependencies: [],
              ports: [{ name: "in_a", direction: "input", width: 1 }],
              ruby_source: "class TopOk; end\n"
            }
          ],
          failed_modules: [],
          diagnostics: []
        )

        expect(result).to be_success

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("success")
        expect(report.dig("summary", "checks_run")).to eq(1)
        expect(report.dig("summary", "checks_failed")).to eq(0)
        expect(report.dig("checks", 0, "profile")).to eq("ao486_trace")
        expect(report.dig("checks", 0, "status")).to eq("skipped")
        expect(report.dig("checks", 0, "reason")).to eq("no_trace_events")
      end
    end

    it "runs ao486_component_parity checks for converted components" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        harness_calls = []
        harness = lambda do |out:, components:, cycles:, seed:, source_root:, cwd:|
          harness_calls << {
            out: out,
            components: components,
            cycles: cycles,
            seed: seed,
            source_root: source_root,
            cwd: cwd
          }

          components.map do |component|
            {
              component: component,
              status: "pass",
              summary: {
                cycles_compared: 4,
                signals_compared: 8,
                pass_count: 8,
                fail_count: 0
              },
              mismatches: []
            }
          end
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_component_parity",
            vectors: 4,
            seed: 123
          },
          translated_modules: [
            { name: "comp_a", dependencies: [], ruby_source: "class CompA; end\n" },
            { name: "comp_b", dependencies: [], ruby_source: "class CompB; end\n" }
          ],
          failed_modules: [],
          diagnostics: [],
          ao486_component_parity_harness: harness
        )

        expect(result).to be_success
        expect(harness_calls.length).to eq(1)
        expect(harness_calls.first[:components]).to eq(%w[comp_a comp_b])
        expect(harness_calls.first[:cycles]).to eq(4)
        expect(harness_calls.first[:seed]).to eq(123)

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("success")
        expect(report.dig("summary", "checks_run")).to eq(2)
        expect(report.dig("summary", "checks_failed")).to eq(0)
        expect(report.fetch("checks").map { |entry| entry.fetch("profile") }.uniq).to eq(["ao486_component_parity"])
        expect(report.fetch("checks").map { |entry| entry.fetch("component") }).to eq(%w[comp_a comp_b])
        expect(File.exist?(report.dig("checks", 0, "report_path"))).to be(true)
      end
    end

    it "fails ao486_component_parity when harness omits component results" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        harness = lambda do |out:, components:, cycles:, seed:, source_root:, cwd:|
          _ = [out, components, cycles, seed, source_root, cwd]
          [
            {
              component: "comp_a",
              status: "pass",
              summary: {
                cycles_compared: 4,
                signals_compared: 8,
                pass_count: 8,
                fail_count: 0
              },
              mismatches: []
            }
          ]
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_component_parity"
          },
          translated_modules: [
            { name: "comp_a", dependencies: [], ruby_source: "class CompA; end\n" },
            { name: "comp_b", dependencies: [], ruby_source: "class CompB; end\n" }
          ],
          failed_modules: [],
          diagnostics: [],
          ao486_component_parity_harness: harness
        )

        expect(result).to be_failure

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("failure")
        expect(report.dig("summary", "checks_run")).to eq(2)
        expect(report.dig("summary", "checks_failed")).to eq(1)
        missing = report.fetch("checks").find { |entry| entry.fetch("component") == "comp_b" }
        expect(missing.fetch("status")).to eq("tool_failure")
        expect(missing.fetch("reason")).to eq("missing_component_result")
      end
    end

    it "runs ao486_program_parity checks for ao486 top" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        harness_calls = []
        harness = lambda do |out:, top:, cycles:, source_root:, cwd:|
          harness_calls << {
            out: out,
            top: top,
            cycles: cycles,
            source_root: source_root,
            cwd: cwd
          }
          {
            top: top,
            status: "pass",
            summary: {
              cycles_requested: cycles,
              pc_events_compared: 4,
              instruction_events_compared: 4,
              write_events_compared: 1,
              memory_words_compared: 5,
              pass_count: 14,
              fail_count: 0,
              first_mismatch: nil
            },
            mismatches: [],
            traces: {
              reference: {
                pc_sequence: [0xFFFF_FFF0],
                instruction_sequence: [0x0000_00EA],
                memory_writes: [],
                memory_contents: { "00000200" => 0x0000_1234 }
              },
              generated_verilog: {},
              generated_ir: {}
            }
          }
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_program_parity",
            trace_cycles: 64
          },
          translated_modules: [
            { name: "ao486", dependencies: [], ruby_source: "class Ao486; end\n" }
          ],
          failed_modules: [],
          diagnostics: [],
          ao486_program_parity_harness: harness
        )

        expect(result).to be_success
        expect(harness_calls.length).to eq(1)
        expect(harness_calls.first[:top]).to eq("ao486")
        expect(harness_calls.first[:cycles]).to eq(64)

        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("success")
        expect(report.dig("summary", "checks_run")).to eq(1)
        expect(report.dig("summary", "checks_failed")).to eq(0)
        check = report.fetch("checks").first
        expect(check.fetch("profile")).to eq("ao486_program_parity")
        expect(check.fetch("status")).to eq("pass")
        expect(check.dig("summary", "pc_events_compared")).to eq(4)
        expect(File.exist?(check.fetch("report_path"))).to be(true)
      end
    end

    it "prunes prior profile report artifacts across consecutive runs" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        translated_modules = [
          { name: "ao486", dependencies: [], ruby_source: "class Ao486; end\n" }
        ]

        first = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_trace",
            expected_trace_events: { "ao486" => [{ "pc" => "0x1000" }] },
            actual_trace_events: { "ao486" => [{ "pc" => "0x1000" }] }
          },
          translated_modules: translated_modules,
          failed_modules: [],
          diagnostics: []
        )

        expect(first).to be_success
        first_report = JSON.parse(File.read(first.report_path))
        trace_report_path = first_report.dig("checks", 0, "report_path")
        expect(File.exist?(trace_report_path)).to be(true)

        harness = lambda do |out:, top:, cycles:, source_root:, cwd:|
          _ = [out, top, cycles, source_root, cwd]
          {
            top: "ao486",
            status: "pass",
            summary: {
              cycles_requested: 64,
              pc_events_compared: 1,
              instruction_events_compared: 1,
              write_events_compared: 0,
              memory_words_compared: 1,
              pass_count: 3,
              fail_count: 0,
              first_mismatch: nil
            },
            mismatches: [],
            traces: {
              reference: {},
              generated_verilog: {},
              generated_ir: {}
            }
          }
        end

        second = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_program_parity",
            trace_cycles: 64
          },
          translated_modules: translated_modules,
          failed_modules: [],
          diagnostics: [],
          ao486_program_parity_harness: harness
        )

        expect(second).to be_success
        second_report = JSON.parse(File.read(second.report_path))
        expect(second_report.dig("checks", 0, "profile")).to eq("ao486_program_parity")
        program_report_path = second_report.dig("checks", 0, "report_path")
        expect(File.exist?(program_report_path)).to be(true)
        expect(File.exist?(trace_report_path)).to be(false)
      end
    end

    it "reports ao486_program_parity tool failures from harness exceptions" do
      Dir.mktmpdir do |dir|
        out = File.join(dir, "out")
        harness = lambda do |out:, top:, cycles:, source_root:, cwd:|
          _ = [out, top, cycles, source_root, cwd]
          raise "program harness exploded"
        end

        result = described_class.run(
          out: out,
          project_slug: "demo_import",
          options: {
            src: [dir],
            check_profile: "ao486_program_parity"
          },
          translated_modules: [
            { name: "ao486", dependencies: [], ruby_source: "class Ao486; end\n" }
          ],
          failed_modules: [],
          diagnostics: [],
          ao486_program_parity_harness: harness
        )

        expect(result).to be_failure
        report = JSON.parse(File.read(result.report_path))
        expect(report.fetch("status")).to eq("failure")
        expect(report.dig("summary", "checks_run")).to eq(1)
        expect(report.dig("summary", "checks_failed")).to eq(1)
        check = report.fetch("checks").first
        expect(check.fetch("profile")).to eq("ao486_program_parity")
        expect(check.fetch("status")).to eq("tool_failure")
        expect(check.fetch("reason")).to eq("harness_error")
      end
    end
  end
end
