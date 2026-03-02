# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/checks/ao486_component_parity_harness"

RSpec.describe RHDL::Import::Checks::Ao486ComponentParityHarness do
  subject(:harness) do
    described_class.new(
      out: ".",
      components: [],
      cycles: 1,
      seed: 1,
      source_root: ".",
      cwd: Dir.pwd
    )
  end

  describe "#equivalent_signal_values?" do
    it "treats x/z pattern digits as wildcards while preserving known hex digits" do
      expect(harness.send(:equivalent_signal_values?, "00ffxx", 0x00FF12, width: 24)).to be(true)
      expect(harness.send(:equivalent_signal_values?, "00ffxx", 0x01FF12, width: 24)).to be(false)
    end

    it "allows unknown single-bit original values to match deterministic IR values" do
      expect(harness.send(:equivalent_signal_values?, "x", 0, width: 1)).to be(true)
      expect(harness.send(:equivalent_signal_values?, "z", 1, width: 1)).to be(true)
    end

    it "treats unknown candidate digits as wildcard-compatible with known pattern digits" do
      expect(harness.send(:equivalent_signal_values?, "x00000000xxxxxxxx", "00000000xxxxxxxxx", width: 68)).to be(true)
    end
  end

  describe "#compare_three_way" do
    it "counts wildcard-compatible x/z comparisons as passes" do
      output_ports = [{ name: "sig", width: 8 }]
      original_trace = [{ "sig" => "xx" }]
      generated_trace = [{ "sig" => "0f" }]
      ir_trace = [{ "sig" => 0x0F }]

      result = harness.send(
        :compare_three_way,
        output_ports: output_ports,
        original_trace: original_trace,
        generated_trace: generated_trace,
        ir_trace: ir_trace
      )

      expect(result.dig(:summary, :fail_count)).to eq(0)
      expect(result[:mismatches]).to eq([])
    end
  end
end
