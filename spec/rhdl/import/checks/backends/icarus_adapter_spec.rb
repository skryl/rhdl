# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/checks/backends/icarus_adapter"

RSpec.describe RHDL::Import::Checks::Backends::IcarusAdapter do
  let(:status_like) { Struct.new(:exitstatus) }

  describe "#call" do
    it "returns a normalized success contract with deterministic command metadata" do
      calls = []
      runner = lambda do |command, chdir:, env:|
        calls << { command: command, chdir: chdir, env: env }
        ["icarus stdout", "icarus stderr", status_like.new(0)]
      end

      adapter = described_class.new(runner: runner)
      result = adapter.call(
        command: ["iverilog", "-g2012", "-o", "sim.out", "tb.sv"],
        work_dir: "tmp/import_checks",
        env: { "LC_ALL" => "C" }
      )

      expect(calls.length).to eq(1)
      expect(calls.first).to eq(
        command: ["iverilog", "-g2012", "-o", "sim.out", "tb.sv"],
        chdir: File.expand_path("tmp/import_checks"),
        env: { "LC_ALL" => "C" }
      )

      expect(result).to include(
        backend: :icarus,
        status: :ok,
        available: true,
        error: nil
      )
      expect(result.dig(:command, :argv)).to eq(["iverilog", "-g2012", "-o", "sim.out", "tb.sv"])
      expect(result.dig(:command, :shell)).to eq("iverilog -g2012 -o sim.out tb.sv")
      expect(result.dig(:command, :stdout)).to eq("icarus stdout")
      expect(result.dig(:command, :stderr)).to eq("icarus stderr")
      expect(result.dig(:command, :exit_code)).to eq(0)
      expect(result.dig(:command, :chdir)).to eq(File.expand_path("tmp/import_checks"))
      expect(result.dig(:command, :env)).to eq("LC_ALL" => "C")
    end

    it "returns unavailable when the executable is missing" do
      runner = lambda do |_command, chdir:, env:|
        expect(chdir).to eq(File.expand_path("tmp/import_checks"))
        expect(env).to eq({})
        raise Errno::ENOENT, "No such file or directory - iverilog"
      end

      adapter = described_class.new(runner: runner)
      result = adapter.call(command: ["iverilog", "-o", "sim.out", "tb.sv"], work_dir: "tmp/import_checks")

      expect(result).to include(
        backend: :icarus,
        status: :unavailable,
        available: false
      )
      expect(result.dig(:command, :exit_code)).to be_nil
      expect(result.dig(:error, :class)).to eq("Errno::ENOENT")
      expect(result.dig(:error, :message)).to include("iverilog")
    end

    it "returns tool_failure with non-zero exit metadata" do
      runner = lambda do |_command, chdir:, env:|
        expect(chdir).to eq(File.expand_path("tmp/import_checks"))
        expect(env).to eq({})
        ["", "compile failed", status_like.new(2)]
      end

      adapter = described_class.new(runner: runner)
      result = adapter.call(command: ["iverilog", "-o", "sim.out", "tb.sv"], work_dir: "tmp/import_checks")

      expect(result).to include(
        backend: :icarus,
        status: :tool_failure,
        available: true
      )
      expect(result.dig(:command, :stderr)).to eq("compile failed")
      expect(result.dig(:command, :exit_code)).to eq(2)
      expect(result[:error]).to be_nil
    end
  end
end
