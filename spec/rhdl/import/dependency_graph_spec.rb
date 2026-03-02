# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/dependency_graph"

RSpec.describe RHDL::Import::DependencyGraph do
  describe "#reachable_from" do
    it "walks the internal module graph from selected roots" do
      graph = described_class.new(
        modules: [
          { name: "wrapper", dependencies: ["top_bad"] },
          { name: "top_bad", dependencies: ["bad_dep"] },
          { name: "top_ok", dependencies: ["leaf"] },
          { name: "leaf", dependencies: [] }
        ]
      )

      expect(graph.reachable_from(%w[wrapper top_ok])).to eq(%w[leaf top_bad top_ok wrapper])
    end
  end

  describe "#prune_for_failures" do
    it "prunes reachable modules that depend on failed modules" do
      graph = described_class.new(
        modules: [
          { name: "wrapper", dependencies: ["top_bad"] },
          { name: "top_bad", dependencies: ["bad_dep"] },
          { name: "top_ok", dependencies: ["leaf"] },
          { name: "leaf", dependencies: [] }
        ]
      )

      pruned = graph.prune_for_failures(
        roots: %w[wrapper top_ok],
        failed_modules: ["bad_dep"]
      )

      expect(pruned).to eq(
        kept: %w[leaf top_ok],
        pruned: [
          { name: "top_bad", failed_dependencies: ["bad_dep"] },
          { name: "wrapper", failed_dependencies: ["bad_dep"] }
        ]
      )
    end
  end
end
