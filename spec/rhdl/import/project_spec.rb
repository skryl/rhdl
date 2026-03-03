# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "rhdl/import/pipeline"
require "tmpdir"

RSpec.describe RHDL::Import do
  def build_pipeline_result(status:, out_dir:, converted_modules:, failed_modules:, checks:)
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

  describe ".project" do
    it "returns a success result for a full-success flow" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        expected_result = build_pipeline_result(
          status: :success,
          out_dir: out_dir,
          converted_modules: ["top_ok"],
          failed_modules: [],
          checks: [{ top: "top_ok", status: "pass" }]
        )
        allow(RHDL::Import::Pipeline).to receive(:run).and_return(expected_result)

        result = described_class.project(src: [dir], out: out_dir, top: ["top_ok"])

        expect(RHDL::Import::Pipeline).to have_received(:run)
        expect(result).to be(expected_result)
        expect(result).to be_success

        normalized_report = assert_import_report_skeleton!(result.report, status: :success)
        expect(normalized_report.dig("modules", "failed")).to eq([])
      end
    end

    it "returns a failure result for partial conversion with partial output" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        expected_result = build_pipeline_result(
          status: :failure,
          out_dir: out_dir,
          converted_modules: ["top_ok"],
          failed_modules: [{ name: "top_bad", code: "unsupported", message: "unsupported construct" }],
          checks: []
        )
        allow(RHDL::Import::Pipeline).to receive(:run).and_return(expected_result)

        result = described_class.project(src: [dir], out: out_dir, top: ["top_ok"])

        expect(RHDL::Import::Pipeline).to have_received(:run)
        expect(result).to be(expected_result)
        expect(result).to be_failure
        expect(non_zero_import_exit?(result.failure? ? 1 : 0)).to be(true)

        normalized_report = assert_import_report_skeleton!(result.report, status: :failure)
        expect(normalized_report.dig("modules", "converted")).to include("top_ok")
        expect(normalized_report.dig("modules", "failed")).not_to be_empty
      end
    end

    it "returns a failure result when checks fail after conversion" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        expected_result = build_pipeline_result(
          status: :failure,
          out_dir: out_dir,
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
        allow(RHDL::Import::Pipeline).to receive(:run).and_return(expected_result)

        result = described_class.project(src: [dir], out: out_dir, top: ["top_ok"], check: true)

        expect(RHDL::Import::Pipeline).to have_received(:run)
        expect(result).to be(expected_result)
        expect(result).to be_failure

        normalized_report = assert_import_report_skeleton!(result.report, status: :failure)
        expect(normalized_report.dig("modules", "failed")).to eq([])
        expect(normalized_report.dig("summary", "checks_failed")).to eq(1)
        expect(normalized_report.fetch("checks").length).to eq(1)
      end
    end

    it "returns a failure result when source files are provided but no modules are mapped" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        source_file = File.join(dir, "top.v")
        File.write(source_file, "module top; endmodule\n")

        result = described_class.project(
          out: out_dir,
          src: [dir],
          resolved_input: {
            source_files: [source_file],
            include_dirs: [],
            defines: []
          },
          mapped_modules: [],
          no_check: true
        )

        expect(result).to be_failure

        normalized_report = assert_import_report_skeleton!(result.report, status: :failure)
        expect(normalized_report.dig("modules", "failed")).to include(
          a_hash_including(
            "name" => "import",
            "code" => "no_modules_detected"
          )
        )
      end
    end

    it "forwards ingestion and missing-module options through resolver and frontend input" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        source_file = File.join(dir, "top.v")
        File.write(source_file, "module top; endmodule\n")

        captured_frontend_input = nil

        input_resolver = lambda do |**kwargs|
          expect(kwargs[:dependency_resolution]).to eq("parent_root_auto_scan")
          expect(kwargs[:compile_unit_filter]).to eq("modules_only")
          {
            source_files: [source_file],
            include_dirs: [],
            defines: [],
            frontend_input: {
              source_files: [source_file],
              include_dirs: [],
              defines: []
            }
          }
        end

        frontend_adapter = lambda do |resolved_input:, **_kwargs|
          captured_frontend_input = resolved_input
          {
            payload: {
              sources: [{ id: 1, path: source_file }],
              modules: [
                {
                  name: "top",
                  source_id: 1,
                  span: { line: 1, column: 1, end_line: 1, end_column: 3 }
                }
              ]
            },
            metadata: {}
          }
        end

        result = described_class.project(
          out: out_dir,
          src: [dir],
          dependency_resolution: "parent_root_auto_scan",
          compile_unit_filter: "modules_only",
          missing_modules: "blackbox_stubs",
          input_resolver: input_resolver,
          frontend_adapter: frontend_adapter,
          no_check: true
        )

        expect(result).to be_success
        expect(captured_frontend_input[:missing_modules]).to eq("blackbox_stubs")
      end
    end

    it "expands ao486 sibling source roots for ao486_program_parity input resolution" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        rtl_dir = File.join(dir, "rtl")
        ao486_dir = File.join(rtl_dir, "ao486")
        common_dir = File.join(rtl_dir, "common")
        cache_dir = File.join(rtl_dir, "cache")
        FileUtils.mkdir_p([ao486_dir, common_dir, cache_dir])

        source_file = File.join(ao486_dir, "top.v")
        File.write(source_file, "module ao486; endmodule\n")

        expected_result = build_pipeline_result(
          status: :success,
          out_dir: out_dir,
          converted_modules: ["ao486"],
          failed_modules: [],
          checks: []
        )
        allow(RHDL::Import::Pipeline).to receive(:run).and_return(expected_result)

        input_resolver = lambda do |**kwargs|
          expect(kwargs[:src]).to include(ao486_dir, common_dir, cache_dir)
          {
            source_files: [source_file],
            include_dirs: [],
            defines: [],
            frontend_input: {
              source_files: [source_file],
              include_dirs: [],
              defines: []
            }
          }
        end

        result = described_class.project(
          out: out_dir,
          src: [ao486_dir],
          top: ["ao486"],
          check_profile: "ao486_program_parity",
          input_resolver: input_resolver,
          mapped_modules: [
            {
              name: "ao486",
              dependencies: [],
              ports: []
            }
          ],
          no_check: true
        )

        expect(result).to be_success
      end
    end

    it "passes frontend wrapper metadata through to the normalizer" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        source_file = File.join(dir, "top.v")
        File.write(source_file, "module top; endmodule\n")

        frontend_result = {
          payload: {
            version: "5.044",
            modulesp: [
              { type: "MODULE", name: "top", loc: "e,1:1,1:3" }
            ]
          },
          metadata: {
            frontend_meta: {
              files: {
                "e" => { filename: source_file }
              }
            },
            command: {
              argv: ["verilator", "--json-only"],
              chdir: dir
            }
          }
        }
        observed_payload = nil
        normalizer = lambda do |raw_payload|
          observed_payload = raw_payload
          {
            schema_version: 1,
            design: {
              modules: [
                {
                  name: "top",
                  source_id: 1,
                  span: {
                    source_id: 1,
                    source_path: source_file,
                    line: 1,
                    column: 1,
                    end_line: 1,
                    end_column: 3
                  }
                }
              ]
            },
            diagnostics: []
          }
        end
        mapper = lambda do |_normalized_payload|
          {
            modules: [
              { name: "top", dependencies: [] }
            ],
            diagnostics: []
          }
        end

        result = described_class.project(
          out: out_dir,
          src: [dir],
          resolved_input: {
            source_files: [source_file],
            include_dirs: [],
            defines: []
          },
          frontend_result: frontend_result,
          frontend_normalizer: normalizer,
          mapper: mapper,
          translated_modules: [{ name: "top", source: "class Top < RHDL::Component\nend\n" }],
          no_check: true
        )

        expect(result).to be_success
        expect(observed_payload).to eq(frontend_result)
      end
    end

    it "propagates mapped module source paths into translated module metadata" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        rtl_dir = File.join(dir, "rtl", "cluster")
        source_file = File.join(rtl_dir, "top.v")
        FileUtils.mkdir_p(rtl_dir)
        File.write(source_file, "module top; endmodule\n")

        expected_result = build_pipeline_result(
          status: :success,
          out_dir: out_dir,
          converted_modules: ["top"],
          failed_modules: [],
          checks: []
        )
        captured_translated_modules = nil
        allow(RHDL::Import::Pipeline).to receive(:run) do |**kwargs|
          captured_translated_modules = kwargs[:translated_modules]
          expected_result
        end

        translator = instance_double("Translator")
        allow(translator).to receive(:translate_module).and_return("class Top < RHDL::Component\nend\n")

        result = described_class.project(
          out: out_dir,
          src: [dir],
          resolved_input: {
            source_files: [source_file],
            include_dirs: [],
            defines: []
          },
          mapped_modules: [
            {
              name: "top",
              dependencies: [],
              span: {
                source_path: source_file
              }
            }
          ],
          translator: translator,
          no_check: true
        )

        expect(result).to be_success
        expect(captured_translated_modules).to include(
          a_hash_including(
            name: "top",
            source_path: source_file
          )
        )
      end
    end

    it "converts wrapped frontend modules and writes module files" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        top_file = File.join(dir, "top.sv")
        leaf_file = File.join(dir, "leaf.v")
        File.write(top_file, "module top; endmodule\n")
        File.write(leaf_file, "module leaf; endmodule\n")

        frontend_result = {
          payload: {
            version: "5.044",
            type: "NETLIST",
            modulesp: [
              { type: "MODULE", name: "top", loc: "e,1:8,1:11" },
              { type: "MODULE", name: "leaf", loc: "f,1:8,1:12" }
            ]
          },
          metadata: {
            frontend_meta: {
              files: {
                "e" => { filename: top_file },
                "f" => { filename: leaf_file }
              }
            },
            command: {
              argv: ["verilator", "--json-only"],
              chdir: dir
            }
          }
        }

        result = described_class.project(
          out: out_dir,
          src: [dir],
          resolved_input: {
            source_files: [top_file, leaf_file],
            include_dirs: [],
            defines: []
          },
          frontend_result: frontend_result,
          no_check: true
        )

        expect(result).to be_success
        expect(result.converted_modules).to eq(%w[leaf top])

        module_root = File.join(out_dir, "lib", "out", "modules")
        expect(File.exist?(File.join(module_root, "leaf.rb"))).to be(true)
        expect(File.exist?(File.join(module_root, "top.rb"))).to be(true)

        normalized_report = assert_import_report_skeleton!(result.report, status: :success)
        expect(normalized_report.dig("summary", "converted_modules")).to eq(2)
        expect(normalized_report.fetch("checks")).to eq([])
      end
    end

    it "forwards ao486 trace harness options through project pipeline options" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        captured_options = nil

        expected_result = build_pipeline_result(
          status: :success,
          out_dir: out_dir,
          converted_modules: ["ao486"],
          failed_modules: [],
          checks: []
        )

        allow(RHDL::Import::Pipeline).to receive(:run) do |**kwargs|
          captured_options = kwargs[:options]
          expected_result
        end

        result = described_class.project(
          out: out_dir,
          src: [dir],
          resolved_input: {
            source_files: [],
            include_dirs: [],
            defines: []
          },
          mapped_modules: [],
          translated_modules: [{ name: "ao486", source: "class Ao486 < RHDL::Component\nend\n" }],
          check_profile: "ao486_trace",
          trace_cycles: 64,
          trace_reference_root: "/tmp/ao486_ref",
          trace_converted_export_mode: "dsl_super",
          no_check: true
        )

        expect(result).to be_success
        expect(captured_options).to include(
          check_profile: "ao486_trace",
          trace_cycles: 64,
          trace_reference_root: "/tmp/ao486_ref",
          trace_converted_export_mode: "dsl_super"
        )
      end
    end

    it "fails import in strict recovery mode when lowered constructs are reported" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        source_file = File.join(dir, "top.v")
        File.write(source_file, "module top; endmodule\n")

        result = described_class.project(
          out: out_dir,
          src: [dir],
          recovery_mode: "strict",
          resolved_input: {
            source_files: [source_file],
            include_dirs: [],
            defines: []
          },
          mapped_modules: [
            {
              name: "top",
              dependencies: []
            }
          ],
          translated_modules: [{ name: "top", source: "class Top < RHDL::Component\nend\n" }],
          diagnostics: [
            {
              severity: "warning",
              code: "recovery_lowered",
              module: "top",
              construct: "loop",
              message: "loop lowered to fallback form"
            }
          ],
          no_check: true
        )

        expect(result).to be_failure
        expect(result.failed_modules).to include(
          a_hash_including(
            name: "import",
            code: "recovery_strict_failure"
          )
        )

        normalized_report = assert_import_report_skeleton!(result.report, status: :failure)
        expect(normalized_report.dig("recovery", "summary", "lowered_count")).to eq(1)
        expect(normalized_report.dig("recovery", "summary", "nonrecoverable_count")).to eq(0)
      end
    end

    it "warns and continues when surelog hints are unavailable" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        source_file = File.join(dir, "top.v")
        File.write(source_file, "module top; endmodule\n")

        hint_adapter = lambda do |**_kwargs|
          raise StandardError, "surelog executable not found"
        end

        result = described_class.project(
          out: out_dir,
          src: [dir],
          hint_backend: "surelog",
          surelog_hint_adapter: hint_adapter,
          resolved_input: {
            source_files: [source_file],
            include_dirs: [],
            defines: []
          },
          normalized_payload: {
            schema_version: 1,
            design: {
              modules: [
                {
                  name: "top",
                  source_id: 1,
                  span: {
                    source_id: 1,
                    source_path: source_file,
                    line: 1,
                    column: 1,
                    end_line: 1,
                    end_column: 3
                  }
                }
              ]
            },
            diagnostics: []
          },
          mapper: lambda { |_payload|
            {
              modules: [{ name: "top", dependencies: [] }],
              diagnostics: []
            }
          },
          translated_modules: [{ name: "top", source: "class Top < RHDL::Component\nend\n" }],
          no_check: true
        )

        expect(result).to be_success
        normalized_report = assert_import_report_skeleton!(result.report, status: :success)
        warning_codes = normalized_report.fetch("diagnostics").map { |entry| entry["code"] }
        expect(warning_codes).to include("hint_backend_unavailable")
        expect(normalized_report.dig("hints", "backend")).to eq("surelog")
        expect(normalized_report.dig("hints", "available")).to eq(false)
      end
    end

    it "records deterministic hints summary counters in project reports" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        source_file = File.join(dir, "top.v")
        File.write(source_file, "module top; endmodule\n")

        hint_adapter = lambda do |**_kwargs|
          {
            backend: "surelog",
            available: true,
            hints: [
              {
                module: "top",
                construct_family: "process",
                construct_kind: "always_ff",
                confidence: "high",
                data: { process_index: 0, clock: "clk" }
              }
            ],
            diagnostics: [
              {
                severity: "warning",
                code: "hint_conflict",
                module: "top",
                message: "conflicting hint candidates"
              }
            ],
            summary: {
              extracted_count: 3,
              applied_count: 1,
              discarded_count: 2,
              conflict_count: 1
            }
          }
        end

        result = described_class.project(
          out: out_dir,
          src: [dir],
          hint_backend: "surelog",
          surelog_hint_adapter: hint_adapter,
          normalized_payload: {
            schema_version: 1,
            design: {
              modules: [
                {
                  name: "top",
                  source_id: 1,
                  processes: [
                    {
                      kind: "always",
                      domain: "sequential",
                      sensitivity: [],
                      statements: []
                    }
                  ],
                  span: {
                    source_id: 1,
                    source_path: source_file,
                    line: 1,
                    column: 1,
                    end_line: 1,
                    end_column: 3
                  }
                }
              ]
            },
            diagnostics: []
          },
          mapper: lambda do |_payload|
            {
              modules: [{ name: "top", dependencies: [] }],
              diagnostics: []
            }
          end,
          translated_modules: [{ name: "top", source: "class Top < RHDL::Component\nend\n" }],
          no_check: true
        )

        expect(result).to be_success
        normalized_report = assert_import_report_skeleton!(result.report, status: :success)
        expect(normalized_report.dig("hints", "summary")).to eq(
          "extracted_count" => 3,
          "applied_count" => 1,
          "discarded_count" => 2,
          "conflict_count" => 1
        )
      end
    end

    it "promotes if statements to case using hints under prefer_hint policy" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        source_file = File.join(dir, "top.v")
        File.write(source_file, "module top; endmodule\n")

        captured_payload = nil
        hint_adapter = lambda do |**_kwargs|
          {
            backend: "surelog",
            available: true,
            hints: [
              {
                module: "top",
                construct_family: "statement",
                construct_kind: "case_from_if",
                confidence: "high",
                span: {
                  source_path: source_file,
                  line: 1,
                  column: 1
                },
                data: {
                  process_index: 0,
                  statement_index: 0,
                  case: {
                    kind: "case",
                    selector: { kind: "identifier", name: "sel" },
                    items: [
                      {
                        values: [{ kind: "number", value: 0, base: 10, signed: false }],
                        body: [
                          {
                            kind: "blocking_assign",
                            target: { kind: "identifier", name: "y" },
                            value: { kind: "number", value: 1, base: 10, signed: false }
                          }
                        ]
                      }
                    ],
                    default: []
                  }
                }
              }
            ],
            diagnostics: [],
            summary: {
              extracted_count: 1,
              applied_count: 1,
              discarded_count: 0,
              conflict_count: 0
            }
          }
        end

        result = described_class.project(
          out: out_dir,
          src: [dir],
          hint_backend: "surelog",
          hint_conflict_policy: "prefer_hint",
          surelog_hint_adapter: hint_adapter,
          normalized_payload: {
            schema_version: 1,
            design: {
              modules: [
                {
                  name: "top",
                  source_id: 1,
                  processes: [
                    {
                      kind: "always",
                      domain: "combinational",
                      sensitivity: [],
                      statements: [
                        {
                          kind: "if",
                          condition: { kind: "identifier", name: "sel" },
                          then: [],
                          else: []
                        }
                      ]
                    }
                  ],
                  span: {
                    source_id: 1,
                    source_path: source_file,
                    line: 1,
                    column: 1,
                    end_line: 1,
                    end_column: 3
                  }
                }
              ]
            },
            diagnostics: []
          },
          mapper: lambda do |payload|
            captured_payload = payload
            {
              modules: [{ name: "top", dependencies: [] }],
              diagnostics: []
            }
          end,
          translated_modules: [{ name: "top", source: "class Top < RHDL::Component\nend\n" }],
          no_check: true
        )

        expect(result).to be_success
        statement = captured_payload.dig(:design, :modules, 0, :processes, 0, :statements, 0)
        expect(statement[:kind]).to eq("case")
        expect(statement[:origin]).to eq("hint")
        expect(statement[:provenance]).to include(
          source: "surelog_hint",
          construct_kind: "case_from_if",
          confidence: "high"
        )

        normalized_report = assert_import_report_skeleton!(result.report, status: :success)
        expect(normalized_report.dig("hints", "summary", "applied_count")).to eq(1)
      end
    end

    it "keeps AST statement under prefer_ast hint conflict policy and reports conflicts" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        source_file = File.join(dir, "top.v")
        File.write(source_file, "module top; endmodule\n")

        captured_payload = nil
        hint_adapter = lambda do |**_kwargs|
          {
            backend: "surelog",
            available: true,
            hints: [
              {
                module: "top",
                construct_family: "statement",
                construct_kind: "case_from_if",
                confidence: "high",
                data: {
                  process_index: 0,
                  statement_index: 0,
                  case: {
                    kind: "case",
                    selector: { kind: "identifier", name: "sel" },
                    items: [],
                    default: []
                  }
                }
              }
            ],
            diagnostics: [],
            summary: {
              extracted_count: 1,
              applied_count: 1,
              discarded_count: 0,
              conflict_count: 0
            }
          }
        end

        result = described_class.project(
          out: out_dir,
          src: [dir],
          hint_backend: "surelog",
          hint_conflict_policy: "prefer_ast",
          surelog_hint_adapter: hint_adapter,
          normalized_payload: {
            schema_version: 1,
            design: {
              modules: [
                {
                  name: "top",
                  source_id: 1,
                  processes: [
                    {
                      kind: "always",
                      domain: "combinational",
                      sensitivity: [],
                      statements: [
                        {
                          kind: "if",
                          condition: { kind: "identifier", name: "sel" },
                          then: [],
                          else: []
                        }
                      ]
                    }
                  ],
                  span: {
                    source_id: 1,
                    source_path: source_file,
                    line: 1,
                    column: 1,
                    end_line: 1,
                    end_column: 3
                  }
                }
              ]
            },
            diagnostics: []
          },
          mapper: lambda do |payload|
            captured_payload = payload
            {
              modules: [{ name: "top", dependencies: [] }],
              diagnostics: []
            }
          end,
          translated_modules: [{ name: "top", source: "class Top < RHDL::Component\nend\n" }],
          no_check: true
        )

        expect(result).to be_success
        statement = captured_payload.dig(:design, :modules, 0, :processes, 0, :statements, 0)
        expect(statement[:kind]).to eq("if")

        normalized_report = assert_import_report_skeleton!(result.report, status: :success)
        conflict_entries = normalized_report.fetch("diagnostics").select { |entry| entry["code"] == "hint_conflict" }
        expect(conflict_entries).not_to be_empty
        expect(normalized_report.dig("hints", "summary", "conflict_count")).to be >= 1
      end
    end

    it "filters hints below minimum confidence before fusion" do
      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "out")
        source_file = File.join(dir, "top.v")
        File.write(source_file, "module top; endmodule\n")

        captured_payload = nil
        hint_adapter = lambda do |**_kwargs|
          {
            backend: "surelog",
            available: true,
            hints: [
              {
                module: "top",
                construct_family: "process",
                construct_kind: "always_ff",
                confidence: "medium",
                data: { process_index: 0 }
              }
            ],
            diagnostics: [],
            summary: {
              extracted_count: 1,
              applied_count: 1,
              discarded_count: 0,
              conflict_count: 0
            }
          }
        end

        result = described_class.project(
          out: out_dir,
          src: [dir],
          hint_backend: "surelog",
          hint_min_confidence: "high",
          surelog_hint_adapter: hint_adapter,
          normalized_payload: {
            schema_version: 1,
            design: {
              modules: [
                {
                  name: "top",
                  source_id: 1,
                  processes: [
                    {
                      kind: "always",
                      domain: "combinational",
                      sensitivity: [],
                      statements: []
                    }
                  ],
                  span: {
                    source_id: 1,
                    source_path: source_file,
                    line: 1,
                    column: 1,
                    end_line: 1,
                    end_column: 3
                  }
                }
              ]
            },
            diagnostics: []
          },
          mapper: lambda do |payload|
            captured_payload = payload
            {
              modules: [{ name: "top", dependencies: [] }],
              diagnostics: []
            }
          end,
          translated_modules: [{ name: "top", source: "class Top < RHDL::Component\nend\n" }],
          no_check: true
        )

        expect(result).to be_success
        process_entry = captured_payload.dig(:design, :modules, 0, :processes, 0)
        expect(process_entry[:intent]).to be_nil

        normalized_report = assert_import_report_skeleton!(result.report, status: :success)
        below_confidence = normalized_report.fetch("diagnostics").select do |entry|
          entry["code"] == "hint_below_min_confidence"
        end
        expect(below_confidence).not_to be_empty
        expect(normalized_report.dig("hints", "summary", "applied_count")).to eq(0)
      end
    end
  end
end
