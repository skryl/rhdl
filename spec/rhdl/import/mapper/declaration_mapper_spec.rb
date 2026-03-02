# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/mapper/declaration_mapper"

RSpec.describe RHDL::Import::Mapper::DeclarationMapper do
  let(:nodes) { deep_symbolize(load_import_fixture_json("translator", "declaration_nodes.json")) }

  describe "#map" do
    it "maps supported declaration nodes" do
      diagnostics = []
      expression_mapper = RHDL::Import::Mapper::ExpressionMapper.new(diagnostics: diagnostics)
      mapper = described_class.new(expression_mapper: expression_mapper, diagnostics: diagnostics)

      declaration = mapper.map(nodes.fetch(:supported).first, module_name: "decl_mod")
      scalar = mapper.map(nodes.fetch(:supported).last, module_name: "decl_mod")

      expect(declaration).to be_a(RHDL::Import::IR::Declaration)
      expect(declaration.kind).to eq("logic")
      expect(declaration.width).to be_a(RHDL::Import::IR::Range)
      expect(scalar.width).to be_nil
      expect(diagnostics).to eq([])
    end

    it "emits unsupported diagnostics tags for unknown declaration kinds" do
      diagnostics = []
      expression_mapper = RHDL::Import::Mapper::ExpressionMapper.new(diagnostics: diagnostics)
      mapper = described_class.new(expression_mapper: expression_mapper, diagnostics: diagnostics)

      result = mapper.map(nodes.fetch(:unsupported), module_name: "decl_mod")

      expect(result).to be_nil
      expect(diagnostics.length).to eq(1)
      expect(diagnostics.first[:code]).to eq("unsupported_construct")
      expect(diagnostics.first[:tags]).to include("mapper", "unsupported_construct", "declaration")
      expect(diagnostics.first[:module]).to eq("decl_mod")
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
