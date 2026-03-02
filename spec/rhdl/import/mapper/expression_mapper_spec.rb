# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/mapper/expression_mapper"

RSpec.describe RHDL::Import::Mapper::ExpressionMapper do
  let(:nodes) { deep_symbolize(load_import_fixture_json("translator", "expression_nodes.json")) }

  describe "#map" do
    it "maps supported expression nodes" do
      diagnostics = []
      mapper = described_class.new(diagnostics: diagnostics)

      expression = mapper.map(nodes.fetch(:supported).first, module_name: "expr_mod")
      ternary = mapper.map(nodes.fetch(:supported).last, module_name: "expr_mod")

      expect(expression).to be_a(RHDL::Import::IR::BinaryExpression)
      expect(expression.operator).to eq("&")
      expect(ternary).to be_a(RHDL::Import::IR::TernaryExpression)
      expect(diagnostics).to eq([])
    end

    it "emits unsupported diagnostics tags for unknown expression kinds" do
      diagnostics = []
      mapper = described_class.new(diagnostics: diagnostics)

      result = mapper.map(nodes.fetch(:unsupported), module_name: "expr_mod")

      expect(result).to be_nil
      expect(diagnostics.length).to eq(1)
      expect(diagnostics.first[:code]).to eq("unsupported_construct")
      expect(diagnostics.first[:tags]).to include("mapper", "unsupported_construct", "expression")
      expect(diagnostics.first[:module]).to eq("expr_mod")
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
