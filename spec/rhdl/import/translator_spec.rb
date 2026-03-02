# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/translator"

RSpec.describe RHDL::Import::Translator do
  describe ".translate" do
    it "translates mapped modules into named source artifacts" do
      modules = load_import_fixture_json("translator", "mapped_modules.json").fetch("modules")

      translated = described_class.translate(modules)

      expect(translated).to be_an(Array)
      expect(translated.map { |entry| entry[:name] }).to eq(%w[top_core child_unit])

      first = translated.first
      expect(first[:source]).to include("# source_module: top_core")
      expect(first[:source]).to include("class TopCore < RHDL::Component")
    end
  end
end
