# frozen_string_literal: true

require "shellwords"
require "spec_helper"
require "rhdl/import/frontend/command_builder"

RSpec.describe RHDL::Import::Frontend::CommandBuilder do
  let(:resolved_input) { load_import_fixture_json("frontend", "resolved_input.json") }
  let(:output_paths) do
    {
      frontend_json_path: "/tmp/work/verilator_frontend.json",
      frontend_meta_path: "/tmp/work/verilator_frontend.meta.json"
    }
  end

  describe "#build" do
    it "builds deterministic Verilator argv for a resolved input contract" do
      builder = described_class.new(verilator_bin: "/opt/bin/verilator")

      first = builder.build(resolved_input: resolved_input, **output_paths)
      second = builder.build(resolved_input: resolved_input, **output_paths)

      expect(first).to eq(second)
      expect(first).to eq(
        [
          "/opt/bin/verilator",
          "--json-only",
          "--json-only-output",
          "/tmp/work/verilator_frontend.json",
          "--json-only-meta-output",
          "/tmp/work/verilator_frontend.meta.json",
          "-Wno-fatal",
          "--language",
          "1800-2017",
          "--top-module",
          "top",
          "-Irtl/include",
          "-Ivendor/include",
          "-DENABLE_TRACE",
          "-DWIDTH=32",
          "rtl/top.sv",
          "rtl/alu.sv"
        ]
      )
      expect(builder.shell_command(resolved_input: resolved_input, **output_paths)).to eq(Shellwords.join(first))
    end

    it "normalizes hash and array define shapes into -D flags" do
      builder = described_class.new

      from_hash = builder.build(
        resolved_input: {
          "source_files" => ["rtl/top.sv"],
          "defines" => { "B" => "2", "A" => "1" }
        },
        **output_paths
      )
      from_array = builder.build(
        resolved_input: {
          "source_files" => ["rtl/top.sv"],
          "defines" => ["B=2", "A=1"]
        },
        **output_paths
      )

      expect(from_hash.grep(/\A-D/)).to eq(["-DA=1", "-DB=2"])
      expect(from_array.grep(/\A-D/)).to eq(["-DB=2", "-DA=1"])
    end

    it "adds -Wno-MODMISSING when missing modules policy is blackbox_stubs" do
      builder = described_class.new

      command = builder.build(
        resolved_input: {
          "source_files" => ["rtl/top.sv"],
          "missing_modules" => "blackbox_stubs"
        },
        **output_paths
      )

      expect(command).to include("-Wno-MODMISSING")
    end

    it "raises when source files are missing from the contract" do
      builder = described_class.new

      expect do
        builder.build(
          resolved_input: {},
          **output_paths
        )
      end.to raise_error(ArgumentError, /source files/i)
    end
  end
end
