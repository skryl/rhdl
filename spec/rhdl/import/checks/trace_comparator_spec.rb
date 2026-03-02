# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/checks/trace_comparator"

RSpec.describe RHDL::Import::Checks::TraceComparator do
  describe ".compare" do
    it "passes when canonicalized events match" do
      expected = [
        { "cycle" => 1, "pc" => "0x1000", "state" => { "a" => 1, "b" => 2 } }
      ]
      actual = [
        { "pc" => "0x1000", "cycle" => 1, "state" => { "b" => 2, "a" => 1 } }
      ]

      result = described_class.compare(expected: expected, actual: actual)

      expect(result[:passed]).to be(true)
      expect(result.dig(:summary, :events_compared)).to eq(1)
      expect(result.dig(:summary, :fail_count)).to eq(0)
      expect(result[:mismatches]).to eq([])
    end

    it "reports first mismatch details and length differences" do
      expected = [
        { "pc" => "0x1000", "eax" => 1 },
        { "pc" => "0x1004", "eax" => 2 }
      ]
      actual = [
        { "pc" => "0x1000", "eax" => 9 }
      ]

      result = described_class.compare(expected: expected, actual: actual)

      expect(result[:passed]).to be(false)
      expect(result.dig(:summary, :events_compared)).to eq(2)
      expect(result.dig(:summary, :pass_count)).to eq(0)
      expect(result.dig(:summary, :fail_count)).to eq(2)
      expect(result.dig(:summary, :first_mismatch, :index)).to eq(0)
      expect(result[:mismatches].map { |entry| entry[:index] }).to eq([0, 1])
    end

    it "supports key-filtered trace comparison for deterministic subsets" do
      expected = [
        { "pc" => "0x1000", "eax" => 1, "ebx" => 2 }
      ]
      actual = [
        { "pc" => "0x1000", "eax" => 9, "ebx" => 7 }
      ]

      result = described_class.compare(expected: expected, actual: actual, keys: %w[pc])

      expect(result[:passed]).to be(true)
      expect(result.dig(:summary, :keys)).to eq(["pc"])
      expect(result.dig(:summary, :fail_count)).to eq(0)
    end
  end
end
