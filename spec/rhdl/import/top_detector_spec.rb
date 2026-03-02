# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/top_detector"

RSpec.describe RHDL::Import::TopDetector do
  describe ".detect" do
    let(:modules) do
      [
        { name: "alu_top", dependencies: ["adder", "uart_tx"] },
        { name: "adder", dependencies: [] },
        { name: "uart_tx", dependencies: [] },
        { name: "standalone", dependencies: [] }
      ]
    end

    it "detects tops as modules with no inbound dependency edges" do
      expect(described_class.detect(modules: modules)).to eq(%w[alu_top standalone])
    end

    it "honors explicit tops with de-duplication while preserving order" do
      tops = described_class.detect(
        modules: modules,
        explicit_tops: %w[standalone alu_top standalone]
      )

      expect(tops).to eq(%w[standalone alu_top])
    end

    it "raises when an explicit top is not present in the module set" do
      expect do
        described_class.detect(modules: modules, explicit_tops: ["missing_top"])
      end.to raise_error(ArgumentError, /unknown top modules: missing_top/)
    end
  end
end
