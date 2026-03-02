# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/mapper/statement_mapper"

RSpec.describe RHDL::Import::Mapper::StatementMapper do
  let(:nodes) { deep_symbolize(load_import_fixture_json("translator", "statement_nodes.json")) }

  describe "#map" do
    it "maps continuous assign and if statement nodes" do
      diagnostics = []
      expression_mapper = RHDL::Import::Mapper::ExpressionMapper.new(diagnostics: diagnostics)
      mapper = described_class.new(expression_mapper: expression_mapper, diagnostics: diagnostics)

      assign = mapper.map(nodes.fetch(:supported).first, module_name: "stmt_mod")
      conditional = mapper.map(nodes.fetch(:supported).last, module_name: "stmt_mod")

      expect(assign).to be_a(RHDL::Import::IR::ContinuousAssign)
      expect(conditional).to be_a(RHDL::Import::IR::IfStatement)
      expect(conditional.then_body.first).to be_a(RHDL::Import::IR::BlockingAssign)
      expect(diagnostics).to eq([])
    end

    it "maps case and for statements into import IR nodes" do
      diagnostics = []
      expression_mapper = RHDL::Import::Mapper::ExpressionMapper.new(diagnostics: diagnostics)
      mapper = described_class.new(expression_mapper: expression_mapper, diagnostics: diagnostics)

      case_node = {
        kind: "case",
        selector: { kind: "identifier", name: "op" },
        items: [
          {
            values: [{ kind: "number", value: 0, base: 10, width: 2, signed: false }],
            body: [
              {
                kind: "blocking_assign",
                target: { kind: "identifier", name: "y" },
                value: { kind: "number", value: 1, base: 10, width: 8, signed: false }
              }
            ]
          }
        ],
        default: [
          {
            kind: "blocking_assign",
            target: { kind: "identifier", name: "y" },
            value: { kind: "number", value: 0, base: 10, width: 8, signed: false }
          }
        ]
      }
      for_node = {
        kind: "for",
        var: "i",
        range: { from: 0, to: 3 },
        body: [
          {
            kind: "blocking_assign",
            target: { kind: "identifier", name: "flag" },
            value: { kind: "number", value: 1, base: 10, width: 1, signed: false }
          }
        ]
      }

      mapped_case = mapper.map(case_node, module_name: "stmt_mod")
      mapped_for = mapper.map(for_node, module_name: "stmt_mod")

      expect(mapped_case).to be_a(RHDL::Import::IR::CaseStatement)
      expect(mapped_case.items.first).to be_a(RHDL::Import::IR::CaseItem)
      expect(mapped_for).to be_a(RHDL::Import::IR::ForLoop)
      expect(mapped_for.variable).to eq("i")
      expect(mapped_for.range_start).to eq(0)
      expect(mapped_for.range_end).to eq(3)
      expect(diagnostics).to eq([])
    end

    it "emits unsupported diagnostics tags for unknown statement kinds" do
      diagnostics = []
      expression_mapper = RHDL::Import::Mapper::ExpressionMapper.new(diagnostics: diagnostics)
      mapper = described_class.new(expression_mapper: expression_mapper, diagnostics: diagnostics)

      result = mapper.map(nodes.fetch(:unsupported), module_name: "stmt_mod")

      expect(result).to be_nil
      expect(diagnostics.length).to eq(1)
      expect(diagnostics.first[:code]).to eq("unsupported_construct")
      expect(diagnostics.first[:tags]).to include("mapper", "unsupported_construct", "statement")
      expect(diagnostics.first[:module]).to eq("stmt_mod")
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
