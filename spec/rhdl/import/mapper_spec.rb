# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/mapper"

RSpec.describe RHDL::Import::Mapper do
  describe ".map" do
    let(:payload) { deep_symbolize(load_import_fixture_json("translator", "normalized_payload.json")) }

    it "maps representative normalized frontend payload into Import IR" do
      program = described_class.map(payload)

      expect(program).to be_a(RHDL::Import::IR::Program)
      expect(program.modules.map(&:name)).to include("comb_alu", "seq_counter", "top_with_instance")

      comb = program.modules.find { |mod| mod.name == "comb_alu" }
      comb_assign = comb.statements.first

      expect(comb.parameters.map(&:name)).to eq(["WIDTH"])
      expect(comb.declarations.map(&:name)).to eq(["sum"])
      expect(comb_assign).to be_a(RHDL::Import::IR::ContinuousAssign)
      expect(comb_assign.value).to be_a(RHDL::Import::IR::BinaryExpression)
      expect(comb_assign.value.operator).to eq("+")

      seq = program.modules.find { |mod| mod.name == "seq_counter" }
      process = seq.processes.first
      conditional = process.statements.first

      expect(process).to be_a(RHDL::Import::IR::Process)
      expect(process.domain).to eq("sequential")
      expect(process.sensitivity.map(&:edge)).to eq(["posedge", "negedge"])
      expect(conditional).to be_a(RHDL::Import::IR::IfStatement)
      expect(conditional.then_body.first).to be_a(RHDL::Import::IR::NonBlockingAssign)

      top = program.modules.find { |mod| mod.name == "top_with_instance" }
      instance = top.instances.first

      expect(instance).to be_a(RHDL::Import::IR::Instance)
      expect(instance.module_name).to eq("seq_counter")
      expect(instance.parameter_overrides.map(&:name)).to eq(["WIDTH"])
      expect(instance.connections.map(&:port)).to eq(%w[clk rst_n])

      unsupported = program.diagnostics.select { |diag| diag[:code] == "unsupported_construct" }
      expect(unsupported).not_to be_empty
      expect(unsupported.first[:tags]).to include("mapper", "unsupported_construct", "statement")
      expect(unsupported.first[:module]).to eq("top_with_instance")
      expect(top.statements).to eq([])
    end

    it "maps initial processes without unsupported process diagnostics" do
      program = described_class.map(
        {
          schema_version: 1,
          design: {
            modules: [
              {
                name: "init_mod",
                source_id: 1,
                span: { source_id: 1, source_path: "rtl/init_mod.sv", line: 1, column: 1, end_line: 4, end_column: 3 },
                processes: [
                  {
                    kind: "initial",
                    statements: [
                      {
                        kind: "blocking_assign",
                        target: { kind: "identifier", name: "flag" },
                        value: { kind: "number", value: 1, base: 10, width: nil, signed: false }
                      }
                    ]
                  }
                ]
              }
            ]
          },
          diagnostics: []
        }
      )

      mod = program.modules.first
      process = mod.processes.first

      expect(process).to be_a(RHDL::Import::IR::Process)
      expect(process.domain).to eq("initial")
      expect(process.sensitivity).to eq([])
      expect(program.diagnostics.none? { |diag| diag[:code] == "unsupported_construct" && diag[:family] == "process" }).to be(true)
    end

    it "preserves process intent and provenance metadata from normalized payload" do
      program = described_class.map(
        {
          schema_version: 1,
          design: {
            modules: [
              {
                name: "hinted_proc",
                source_id: 1,
                span: { source_id: 1, source_path: "rtl/hinted_proc.sv", line: 1, column: 1, end_line: 3, end_column: 3 },
                processes: [
                  {
                    kind: "always",
                    domain: "sequential",
                    intent: "always_ff",
                    origin: "hint",
                    provenance: {
                      source: "surelog_hint",
                      construct_kind: "always_ff"
                    },
                    sensitivity: [],
                    statements: []
                  }
                ]
              }
            ]
          },
          diagnostics: []
        }
      )

      process = program.modules.first.processes.first

      expect(process.intent).to eq("always_ff")
      expect(process.origin).to eq("hint")
      expect(process.provenance).to eq(
        source: "surelog_hint",
        construct_kind: "always_ff"
      )
    end

    it "preserves open instance connections when signal expressions are absent" do
      program = described_class.map(
        {
          schema_version: 1,
          design: {
            modules: [
              {
                name: "top_open_conn",
                source_id: 1,
                span: { source_id: 1, source_path: "rtl/top_open_conn.sv", line: 1, column: 1, end_line: 5, end_column: 3 },
                instances: [
                  {
                    name: "u0",
                    module_name: "child",
                    parameter_overrides: [],
                    connections: [
                      { port: "clk", signal: { kind: "identifier", name: "clk" } },
                      { port: "unused", signal: nil }
                    ]
                  }
                ]
              }
            ]
          },
          diagnostics: []
        }
      )

      instance = program.modules.first.instances.first
      open_connection = instance.connections.find { |conn| conn.port == "unused" }

      expect(instance.connections.map(&:port)).to eq(%w[clk unused])
      expect(open_connection).not_to be_nil
      expect(open_connection.signal).to be_nil
    end
  end

  def deep_symbolize(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, inner), memo|
        memo[key.to_sym] = deep_symbolize(inner)
      end
    when Array
      value.map { |inner| deep_symbolize(inner) }
    else
      value
    end
  end
end
