# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/checks/comparator"

RSpec.describe RHDL::Import::Checks::Comparator do
  describe ".compare" do
    it "compares expected and actual values per cycle and signal" do
      expected = {
        0 => { "clk" => 0, "out" => 0 },
        1 => { "clk" => 1, "out" => 1 }
      }
      actual = {
        0 => { "clk" => 0, "out" => 0 },
        1 => { "clk" => 1, "out" => 0 }
      }

      result = described_class.compare(expected: expected, actual: actual)

      expect(result[:passed]).to be(false)
      expect(result[:mismatches]).to eq(
        [
          { cycle: 1, signal: "out", expected: 1, actual: 0 }
        ]
      )
      expect(result[:summary]).to eq(
        cycles_compared: 2,
        signals_compared: 4,
        pass_count: 3,
        fail_count: 1
      )
    end

    it "returns mismatch records in deterministic cycle and signal order" do
      expected = {
        2 => { "z" => 1, "a" => 0 },
        0 => { "b" => 1, "a" => 0 },
        1 => { "a" => 1 }
      }
      actual = {
        0 => { "a" => 1, "b" => 0 },
        2 => { "z" => 0, "a" => 1 },
        1 => { "a" => 0 }
      }

      result = described_class.compare(expected: expected, actual: actual)

      expect(result[:mismatches]).to eq(
        [
          { cycle: 0, signal: "a", expected: 0, actual: 1 },
          { cycle: 0, signal: "b", expected: 1, actual: 0 },
          { cycle: 1, signal: "a", expected: 1, actual: 0 },
          { cycle: 2, signal: "a", expected: 0, actual: 1 },
          { cycle: 2, signal: "z", expected: 1, actual: 0 }
        ]
      )
    end

    it "treats missing cycle/signal values as mismatches in summary counts" do
      expected = [
        { "a" => 0 },
        { "a" => 1, "b" => 1 }
      ]
      actual = {
        0 => { "a" => 0 },
        2 => { "a" => 1 }
      }

      result = described_class.compare(expected: expected, actual: actual)

      expect(result[:mismatches]).to eq(
        [
          { cycle: 1, signal: "a", expected: 1, actual: nil },
          { cycle: 1, signal: "b", expected: 1, actual: nil },
          { cycle: 2, signal: "a", expected: nil, actual: 1 }
        ]
      )
      expect(result[:summary]).to eq(
        cycles_compared: 3,
        signals_compared: 4,
        pass_count: 1,
        fail_count: 3
      )
    end
  end
end
