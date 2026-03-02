# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/checks/runner"

RSpec.describe RHDL::Import::Checks::Runner do
  describe "#call" do
    it "tries Icarus first and selects it when successful" do
      icarus_calls = []
      verilator_calls = []

      icarus_adapter = lambda do |command:, work_dir:, env:|
        icarus_calls << { command: command, work_dir: work_dir, env: env }
        {
          backend: :icarus,
          status: :ok,
          available: true,
          error: nil,
          command: { argv: command, shell: "iverilog -o sim.out", stdout: "", stderr: "", exit_code: 0, chdir: work_dir, env: env }
        }
      end

      verilator_adapter = lambda do |command:, work_dir:, env:|
        verilator_calls << { command: command, work_dir: work_dir, env: env }
        {
          backend: :verilator,
          status: :ok,
          available: true,
          error: nil,
          command: { argv: command, shell: "verilator --binary", stdout: "", stderr: "", exit_code: 0, chdir: work_dir, env: env }
        }
      end

      runner = described_class.new(icarus_adapter: icarus_adapter, verilator_adapter: verilator_adapter)
      result = runner.call(
        work_dir: "tmp/import_checks",
        env: { "LC_ALL" => "C" },
        icarus_command: ["iverilog", "-o", "sim.out"],
        verilator_command: ["verilator", "--binary"]
      )

      expect(icarus_calls.length).to eq(1)
      expect(verilator_calls).to eq([])

      expect(result).to include(
        status: :ok,
        selected_backend: :icarus
      )
      expect(result.fetch(:attempts).map { |entry| entry.fetch(:backend) }).to eq([:icarus])
      expect(result.fetch(:attempts).first).to include(status: :ok, exit_code: 0)
      expect(result.fetch(:selected_result)).to include(backend: :icarus, status: :ok)
      expect(result.fetch(:selected_command)).to include(shell: "iverilog -o sim.out", exit_code: 0)
    end

    it "falls back to Verilator when Icarus is unavailable" do
      icarus_adapter = lambda do |command:, work_dir:, env:|
        {
          backend: :icarus,
          status: :unavailable,
          available: false,
          error: { class: "Errno::ENOENT", message: "iverilog missing" },
          command: { argv: command, shell: "iverilog -o sim.out", stdout: "", stderr: "", exit_code: nil, chdir: work_dir, env: env }
        }
      end

      verilator_adapter = lambda do |command:, work_dir:, env:|
        {
          backend: :verilator,
          status: :ok,
          available: true,
          error: nil,
          command: { argv: command, shell: "verilator --binary", stdout: "", stderr: "", exit_code: 0, chdir: work_dir, env: env }
        }
      end

      runner = described_class.new(icarus_adapter: icarus_adapter, verilator_adapter: verilator_adapter)
      result = runner.call(
        work_dir: "tmp/import_checks",
        icarus_command: ["iverilog", "-o", "sim.out"],
        verilator_command: ["verilator", "--binary"]
      )

      expect(result).to include(
        status: :ok,
        selected_backend: :verilator
      )
      expect(result.fetch(:attempts).map { |entry| entry.fetch(:backend) }).to eq([:icarus, :verilator])
      expect(result.fetch(:attempts).map { |entry| entry.fetch(:status) }).to eq([:unavailable, :ok])
      expect(result.fetch(:selected_result)).to include(backend: :verilator, status: :ok)
      expect(result.fetch(:selected_command)).to include(shell: "verilator --binary", exit_code: 0)
    end

    it "falls back to Verilator when Icarus returns tool_failure" do
      icarus_adapter = lambda do |command:, work_dir:, env:|
        {
          backend: :icarus,
          status: :tool_failure,
          available: true,
          error: nil,
          command: { argv: command, shell: "iverilog -o sim.out", stdout: "", stderr: "compile failed", exit_code: 2, chdir: work_dir, env: env }
        }
      end

      verilator_adapter = lambda do |command:, work_dir:, env:|
        {
          backend: :verilator,
          status: :ok,
          available: true,
          error: nil,
          command: { argv: command, shell: "verilator --binary", stdout: "", stderr: "", exit_code: 0, chdir: work_dir, env: env }
        }
      end

      runner = described_class.new(icarus_adapter: icarus_adapter, verilator_adapter: verilator_adapter)
      result = runner.call(
        work_dir: "tmp/import_checks",
        icarus_command: ["iverilog", "-o", "sim.out"],
        verilator_command: ["verilator", "--binary"]
      )

      expect(result).to include(
        status: :ok,
        selected_backend: :verilator
      )
      expect(result.fetch(:attempts).map { |entry| entry.fetch(:backend) }).to eq([:icarus, :verilator])
      expect(result.fetch(:attempts).map { |entry| entry.fetch(:status) }).to eq([:tool_failure, :ok])
      expect(result.fetch(:attempts).first.fetch(:exit_code)).to eq(2)
      expect(result.fetch(:selected_command)).to include(shell: "verilator --binary", exit_code: 0)
    end

    it "returns the fallback backend failure when both backends fail" do
      icarus_adapter = lambda do |command:, work_dir:, env:|
        {
          backend: :icarus,
          status: :tool_failure,
          available: true,
          error: nil,
          command: { argv: command, shell: "iverilog -o sim.out", stdout: "", stderr: "compile failed", exit_code: 1, chdir: work_dir, env: env }
        }
      end

      verilator_adapter = lambda do |command:, work_dir:, env:|
        {
          backend: :verilator,
          status: :tool_failure,
          available: true,
          error: nil,
          command: { argv: command, shell: "verilator --binary", stdout: "", stderr: "run failed", exit_code: 3, chdir: work_dir, env: env }
        }
      end

      runner = described_class.new(icarus_adapter: icarus_adapter, verilator_adapter: verilator_adapter)
      result = runner.call(
        work_dir: "tmp/import_checks",
        icarus_command: ["iverilog", "-o", "sim.out"],
        verilator_command: ["verilator", "--binary"]
      )

      expect(result).to include(
        status: :tool_failure,
        selected_backend: :verilator
      )
      expect(result.fetch(:attempts).map { |entry| entry.fetch(:backend) }).to eq([:icarus, :verilator])
      expect(result.fetch(:attempts).map { |entry| entry.fetch(:status) }).to eq([:tool_failure, :tool_failure])
      expect(result.fetch(:selected_result)).to include(backend: :verilator, status: :tool_failure)
      expect(result.fetch(:selected_command)).to include(shell: "verilator --binary", exit_code: 3)
    end

    it "runs only Verilator when Icarus command is not provided" do
      icarus_calls = []
      verilator_calls = []

      icarus_adapter = lambda do |command:, work_dir:, env:|
        icarus_calls << { command: command, work_dir: work_dir, env: env }
        {
          backend: :icarus,
          status: :ok,
          available: true,
          error: nil,
          command: { argv: command, shell: "iverilog -o sim.out", stdout: "", stderr: "", exit_code: 0, chdir: work_dir, env: env }
        }
      end

      verilator_adapter = lambda do |command:, work_dir:, env:|
        verilator_calls << { command: command, work_dir: work_dir, env: env }
        {
          backend: :verilator,
          status: :ok,
          available: true,
          error: nil,
          command: { argv: command, shell: "verilator --binary", stdout: "", stderr: "", exit_code: 0, chdir: work_dir, env: env }
        }
      end

      runner = described_class.new(icarus_adapter: icarus_adapter, verilator_adapter: verilator_adapter)
      result = runner.call(
        work_dir: "tmp/import_checks",
        icarus_command: nil,
        verilator_command: ["verilator", "--binary"]
      )

      expect(icarus_calls).to eq([])
      expect(verilator_calls.length).to eq(1)
      expect(result).to include(
        status: :ok,
        selected_backend: :verilator
      )
      expect(result.fetch(:attempts).map { |entry| entry.fetch(:backend) }).to eq([:verilator])
    end

    it "returns unavailable when no backend commands are provided" do
      runner = described_class.new(icarus_adapter: ->(**_) { raise "should not call" }, verilator_adapter: ->(**_) { raise "should not call" })
      result = runner.call(work_dir: "tmp/import_checks", icarus_command: nil, verilator_command: nil)

      expect(result).to include(
        status: :unavailable,
        selected_backend: :none
      )
      expect(result.fetch(:attempts)).to eq([])
      expect(result.dig(:selected_result, :error, :message)).to match(/no backend command configured/)
    end
  end
end
