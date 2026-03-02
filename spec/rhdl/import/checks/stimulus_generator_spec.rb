# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/checks/stimulus_generator"

RSpec.describe RHDL::Import::Checks::StimulusGenerator do
  describe ".generate" do
    let(:top_signature) do
      {
        name: "demo_top",
        ports: [
          { name: "z_bus", direction: "input", width: 8 },
          { name: "a_bus", direction: :in, width: 4 },
          { name: "enable", direction: "input", width: 1 },
          { name: "sum", direction: "output", width: 8 }
        ]
      }
    end

    it "is stable for the same signature, vector count, and seed" do
      first = described_class.generate(top_signature: top_signature, vectors: 5, seed: 1234)
      second = described_class.generate(top_signature: top_signature, vectors: 5, seed: 1234)

      expect(first).to eq(second)
    end

    it "changes when the seed changes" do
      first = described_class.generate(top_signature: top_signature, vectors: 5, seed: 1)
      second = described_class.generate(top_signature: top_signature, vectors: 5, seed: 2)

      expect(first).not_to eq(second)
    end

    it "preserves deterministic vector ordering and input port ordering" do
      generated = described_class.generate(top_signature: top_signature, vectors: 4, seed: 99)

      expect(generated.map { |vector| vector[:cycle] }).to eq([0, 1, 2, 3])
      expect(generated.length).to eq(4)

      generated.each do |vector|
        expect(vector.fetch(:inputs).keys).to eq(%w[z_bus a_bus enable])
        expect(vector.fetch(:inputs)["z_bus"]).to be_between(0, 255)
        expect(vector.fetch(:inputs)["a_bus"]).to be_between(0, 15)
        expect(vector.fetch(:inputs)["enable"]).to be_between(0, 1)
      end
    end
  end
end
