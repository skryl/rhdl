# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/ir"

RSpec.describe RHDL::Import::IR do
  describe RHDL::Import::IR::Program do
    it "materializes a normalized hash for mapped modules and diagnostics" do
      span = RHDL::Import::IR::Span.new(source_id: 1, source_path: "rtl/top.sv", line: 1, column: 1, end_line: 10, end_column: 3)
      declaration = RHDL::Import::IR::Declaration.new(kind: "logic", name: "data", width: nil, span: span)
      module_node = RHDL::Import::IR::Module.new(
        name: "top",
        source_id: 1,
        span: span,
        ports: [],
        parameters: [],
        declarations: [declaration],
        statements: [],
        processes: [],
        instances: []
      )

      program = described_class.new(
        schema_version: 1,
        modules: [module_node],
        diagnostics: [{ code: "unsupported_construct", tags: ["mapper"] }]
      )

      expect(program.to_h).to eq(
        schema_version: 1,
        modules: [
          {
            name: "top",
            source_id: 1,
            span: {
              source_id: 1,
              source_path: "rtl/top.sv",
              line: 1,
              column: 1,
              end_line: 10,
              end_column: 3
            },
            ports: [],
            parameters: [],
            declarations: [
              {
                kind: "logic",
                name: "data",
                width: nil,
                span: {
                  source_id: 1,
                  source_path: "rtl/top.sv",
                  line: 1,
                  column: 1,
                  end_line: 10,
                  end_column: 3
                }
              }
            ],
            statements: [],
            processes: [],
            instances: []
          }
        ],
        diagnostics: [{ code: "unsupported_construct", tags: ["mapper"] }]
      )
    end
  end

  describe "statement node serialization" do
    it "serializes case and for statement IR nodes" do
      selector = RHDL::Import::IR::Identifier.new(name: "op", span: nil)
      assign_value = RHDL::Import::IR::NumberLiteral.new(value: 1, base: 10, width: 8, signed: false, span: nil)
      assign_stmt = RHDL::Import::IR::BlockingAssign.new(
        target: RHDL::Import::IR::Identifier.new(name: "y", span: nil),
        value: assign_value,
        span: nil
      )

      case_item = RHDL::Import::IR::CaseItem.new(
        values: [RHDL::Import::IR::NumberLiteral.new(value: 0, base: 10, width: 2, signed: false, span: nil)],
        body: [assign_stmt],
        span: nil
      )
      case_stmt = RHDL::Import::IR::CaseStatement.new(
        selector: selector,
        items: [case_item],
        default_body: [assign_stmt],
        span: nil
      )
      for_stmt = RHDL::Import::IR::ForLoop.new(
        variable: "i",
        range_start: 0,
        range_end: 3,
        body: [assign_stmt],
        span: nil
      )

      expect(case_stmt.to_h).to include(
        kind: "case",
        selector: include(kind: "identifier", name: "op"),
        items: [include(values: [include(kind: "number", value: 0)])],
        default_body: [include(kind: "blocking_assign")]
      )
      expect(for_stmt.to_h).to eq(
        kind: "for",
        variable: "i",
        range: { from: 0, to: 3 },
        body: [assign_stmt.to_h],
        span: nil
      )
    end

    it "serializes hint provenance metadata on process and case nodes" do
      process = RHDL::Import::IR::Process.new(
        domain: "sequential",
        sensitivity: [],
        statements: [],
        span: nil,
        intent: "always_ff",
        origin: "hint",
        provenance: {
          source: "surelog_hint",
          construct_kind: "always_ff"
        }
      )

      case_stmt = RHDL::Import::IR::CaseStatement.new(
        selector: RHDL::Import::IR::Identifier.new(name: "sel", span: nil),
        items: [],
        default_body: [],
        span: nil,
        qualifier: "unique",
        origin: "hint",
        provenance: {
          source: "surelog_hint",
          construct_kind: "case_from_if"
        }
      )

      expect(process.to_h).to include(
        intent: "always_ff",
        origin: "hint",
        provenance: {
          source: "surelog_hint",
          construct_kind: "always_ff"
        }
      )

      expect(case_stmt.to_h).to include(
        qualifier: "unique",
        origin: "hint",
        provenance: {
          source: "surelog_hint",
          construct_kind: "case_from_if"
        }
      )
    end
  end
end
