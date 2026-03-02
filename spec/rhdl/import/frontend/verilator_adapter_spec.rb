# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"
require "rhdl/import/frontend/verilator_adapter"

RSpec.describe RHDL::Import::Frontend::VerilatorAdapter do
  let(:resolved_input) { load_import_fixture_json("frontend", "resolved_input.json") }
  let(:payload_fixture) { File.read(import_fixture_path("frontend", "verilator_payload.json")) }
  let(:meta_fixture) { File.read(import_fixture_path("frontend", "verilator_meta.json")) }
  let(:status_like) { Struct.new(:exitstatus) }

  describe "#call" do
    it "invokes Verilator and returns raw payload plus command metadata" do
      calls = []
      runner = lambda do |command, chdir:, env:|
        calls << { command: command, chdir: chdir, env: env }
        json_path = command[command.index("--json-only-output") + 1]
        meta_path = command[command.index("--json-only-meta-output") + 1]
        File.write(json_path, payload_fixture)
        File.write(meta_path, meta_fixture)
        ["frontend stdout", "frontend stderr", status_like.new(0)]
      end

      Dir.mktmpdir do |dir|
        adapter = described_class.new(runner: runner)
        result = adapter.call(resolved_input: resolved_input, work_dir: dir, env: { "LC_ALL" => "C" })

        expect(calls.length).to eq(1)
        expect(calls.first[:chdir]).to eq(File.expand_path(dir))
        expect(calls.first[:env]).to eq("LC_ALL" => "C")
        expect(calls.first[:command].first).to eq("verilator")
        expect(calls.first[:command]).to include("--json-only", "--json-only-output", "--json-only-meta-output")

        expect(result.fetch(:payload)).to eq(JSON.parse(payload_fixture))
        expect(result.dig(:metadata, :frontend_meta)).to eq(JSON.parse(meta_fixture))
        expect(result.dig(:metadata, :command, :stdout)).to eq("frontend stdout")
        expect(result.dig(:metadata, :command, :stderr)).to eq("frontend stderr")
        expect(result.dig(:metadata, :command, :exit_code)).to eq(0)
        expect(result.dig(:metadata, :command, :shell)).to include("verilator --json-only")
      end
    end

    it "surfaces exit status and stderr when Verilator fails" do
      runner = lambda do |command, chdir:, env:|
        expect(command.first).to eq("verilator")
        expect(chdir).to be_a(String)
        expect(env).to eq({})
        ["", "%Error: parse failed", status_like.new(2)]
      end

      Dir.mktmpdir do |dir|
        adapter = described_class.new(runner: runner)

        expect do
          adapter.call(resolved_input: resolved_input, work_dir: dir)
        end.to raise_error(RHDL::Import::Frontend::VerilatorAdapter::ExecutionError) { |error|
          expect(error.exit_code).to eq(2)
          expect(error.stderr).to include("parse failed")
          expect(error.command.first).to eq("verilator")
          expect(error.metadata.dig(:command, :exit_code)).to eq(2)
        }
      end
    end

    it "raises when Verilator exits zero but JSON artifacts are missing" do
      runner = lambda do |_command, chdir:, env:|
        expect(chdir).to be_a(String)
        expect(env).to eq({})
        ["", "", status_like.new(0)]
      end

      Dir.mktmpdir do |dir|
        adapter = described_class.new(runner: runner)

        expect do
          adapter.call(resolved_input: resolved_input, work_dir: dir)
        end.to raise_error(
          RHDL::Import::Frontend::VerilatorAdapter::ExecutionError,
          /did not write frontend json artifact/i
        )
      end
    end

    it "parses deeply nested frontend JSON payloads" do
      runner = lambda do |command, chdir:, env:|
        expect(chdir).to be_a(String)
        expect(env).to eq({})
        json_path = command[command.index("--json-only-output") + 1]
        meta_path = command[command.index("--json-only-meta-output") + 1]
        deep_payload = "{\"payload\":#{'[' * 120}0#{']' * 120}}"
        File.write(json_path, deep_payload)
        File.write(meta_path, meta_fixture)
        ["", "", status_like.new(0)]
      end

      Dir.mktmpdir do |dir|
        adapter = described_class.new(runner: runner)
        result = adapter.call(resolved_input: resolved_input, work_dir: dir)
        nested = result.fetch(:payload).fetch("payload")
        120.times do
          expect(nested).to be_a(Array)
          nested = nested.first
        end
        expect(nested).to eq(0)
      end
    end
  end
end
