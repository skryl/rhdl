# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "rhdl/import/frontend/surelog_hint_adapter"

RSpec.describe RHDL::Import::Frontend::SurelogHintAdapter do
  let(:status_like) { Struct.new(:exitstatus) }

  describe "#call" do
    it "returns deterministic backend metadata when surelog is available" do
      runner = lambda do |command, chdir:, env:|
        expect(command).to eq(["surelog", "--version"])
        expect(chdir).to be_a(String)
        expect(env).to eq("LC_ALL" => "C")
        ["Surelog 1.58\n", "", status_like.new(0)]
      end

      Dir.mktmpdir do |dir|
        adapter = described_class.new(runner: runner)
        result = adapter.call(
          resolved_input: {
            source_files: [File.join(dir, "top.sv")],
            surelog_hints: []
          },
          work_dir: dir,
          env: { "LC_ALL" => "C" }
        )

        expect(result).to eq(
          backend: "surelog",
          available: true,
          hints: [],
          diagnostics: [],
          summary: {
            extracted_count: 0,
            applied_count: 0,
            discarded_count: 0,
            conflict_count: 0
          }
        )
      end
    end

    it "extracts canonical hints from a surelog parser run when explicit hints are absent" do
      calls = []
      runner = lambda do |command, chdir:, env:|
        calls << { command: command, chdir: chdir, env: env }
        if command == ["surelog", "--version"]
          expect(env).to eq("LC_ALL" => "C")
          return ["Surelog 1.58\n", "", status_like.new(0)]
        end

        if command.first == "surelog"
          expect(command).to include("-parse", "-sverilog", "-odir", "--top-module", "top")
          expect(command).to include(
            "-I#{File.expand_path('rtl/include')}",
            "+define+ENABLE_TRACE",
            "+define+WIDTH=32",
            File.expand_path("rtl/top.sv")
          )
          expect(chdir).to end_with("/surelog_extract")
          uhdm_dir = command[command.index("-odir") + 1]
          FileUtils.mkdir_p(File.join(uhdm_dir, "slpp_all"))
          File.write(File.join(uhdm_dir, "slpp_all", "surelog.uhdm"), "dummy")
          return ["", "", status_like.new(0)]
        end

        if command.first == "uhdm-dump"
          expect(command.fetch(1)).to end_with("/slpp_all/surelog.uhdm")
          dump = <<~DUMP
            \\_module_inst: (work@top), file:rtl/top.sv, line:1:1, endln:100:1
              \\_always: , line:22:1, endln:30:1
                |vpiAlwaysType:3
              \\_case_stmt: , line:33:1, endln:40:1
                |vpiQualifier:1
          DUMP
          return [dump, "", status_like.new(0)]
        end

        raise "unexpected command: #{command.inspect}"
      end

      Dir.mktmpdir do |dir|
        adapter = described_class.new(runner: runner)
        result = adapter.call(
          resolved_input: {
            source_files: ["rtl/top.sv"],
            include_dirs: ["rtl/include"],
            defines: { "WIDTH" => "32", "ENABLE_TRACE" => nil },
            top_modules: ["top"]
          },
          work_dir: dir,
          env: { "LC_ALL" => "C" }
        )

        expect(calls.length).to eq(3)
        expect(result.fetch(:summary)).to eq(
          extracted_count: 2,
          applied_count: 2,
          discarded_count: 0,
          conflict_count: 0
        )
        expect(result.fetch(:hints)).to eq(
          [
            {
              module: "top",
              construct_family: "process",
              construct_kind: "always_ff",
              confidence: "high",
              span: {
                source_path: "rtl/top.sv",
                line: 22,
                column: 1
              },
              data: { process_index: 0 }
            },
            {
              module: "top",
              construct_family: "statement",
              construct_kind: "case_unique",
              confidence: "medium",
              span: {
                source_path: "rtl/top.sv",
                line: 33,
                column: 1
              }
            }
          ]
        )
      end
    end

    it "normalizes and deterministically orders canonical hint records" do
      runner = lambda do |command, chdir:, env:|
        expect(command).to eq(["surelog", "--version"])
        expect(chdir).to be_a(String)
        expect(env).to eq({})
        ["Surelog 1.58\n", "", status_like.new(0)]
      end

      hints = [
        {
          "module_name" => "top",
          "family" => "process",
          "kind" => "always_ff",
          "confidence" => "high",
          "span" => { "source_path" => "rtl/top.sv", "line" => 30, "column" => 1 },
          "data" => { "clock" => "clk", "reset" => "rst_n" }
        },
        {
          "module" => "alu",
          "construct_family" => "expression",
          "construct_kind" => "case_unique",
          "confidence" => "medium",
          "span" => { "source_path" => "rtl/alu.sv", "line" => 10, "column" => 3 },
          "data" => { "selector" => "op" }
        },
        {
          # invalid and must be discarded
          "construct_family" => "process",
          "construct_kind" => "always_comb"
        }
      ]

      Dir.mktmpdir do |dir|
        adapter = described_class.new(runner: runner)

        first = adapter.call(resolved_input: { surelog_hints: hints }, work_dir: dir)
        second = adapter.call(resolved_input: { surelog_hints: hints.reverse }, work_dir: dir)

        expect(first).to eq(second)
        expect(first.fetch(:hints)).to eq(
          [
            {
              module: "alu",
              construct_family: "expression",
              construct_kind: "case_unique",
              confidence: "medium",
              span: {
                source_path: "rtl/alu.sv",
                line: 10,
                column: 3
              },
              data: { selector: "op" }
            },
            {
              module: "top",
              construct_family: "process",
              construct_kind: "always_ff",
              confidence: "high",
              span: {
                source_path: "rtl/top.sv",
                line: 30,
                column: 1
              },
              data: { clock: "clk", reset: "rst_n" }
            }
          ]
        )
        expect(first.fetch(:summary)).to eq(
          extracted_count: 3,
          applied_count: 2,
          discarded_count: 1,
          conflict_count: 0
        )
        expect(first.fetch(:diagnostics)).to include(
          a_hash_including(
            code: "hint_discarded",
            severity: "warning"
          )
        )
      end
    end

    it "raises BackendUnavailable when surelog executable is unavailable" do
      runner = lambda do |_command, chdir:, env:|
        expect(chdir).to be_a(String)
        expect(env).to eq({})
        raise Errno::ENOENT, "No such file or directory - surelog"
      end

      Dir.mktmpdir do |dir|
        adapter = described_class.new(runner: runner)

        expect do
          adapter.call(resolved_input: { source_files: [] }, work_dir: dir)
        end.to raise_error(RHDL::Import::Frontend::SurelogHintAdapter::BackendUnavailable, /surelog/)
      end
    end
  end
end
