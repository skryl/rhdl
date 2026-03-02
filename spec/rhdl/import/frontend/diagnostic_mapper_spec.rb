# frozen_string_literal: true

require "spec_helper"
require "json"
require "rhdl/import/frontend/source_map"
require "rhdl/import/frontend/diagnostic_mapper"

RSpec.describe RHDL::Import::Frontend::DiagnosticMapper do
  let(:fixture_root) { File.expand_path("../../../fixtures/import/frontend/normalized", __dir__) }

  describe ".map" do
    it "maps and orders diagnostics with normalized spans" do
      input = load_fixture("diagnostic_mapper_input.json")
      expected = load_fixture("expected_mapped_diagnostics.json")

      source_map = RHDL::Import::Frontend::SourceMap.build(input.fetch("sources"))

      mapped = described_class.map(
        diagnostics: input.fetch("diagnostics"),
        source_map: source_map
      )

      expect(mapped).to eq(deep_symbolize(expected))
    end
  end

  def load_fixture(name)
    JSON.parse(File.read(File.join(fixture_root, name)))
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
