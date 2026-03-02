# frozen_string_literal: true

require "spec_helper"
require "rhdl/import/blackbox_stub_generator"

RSpec.describe RHDL::Import::BlackboxStubGenerator do
  describe ".generate" do
    it "emits deterministic stub modules with inferred parameters and ports" do
      modules = described_class.generate(
        signatures: [
          {
            name: "mem_prim",
            parameters: %w[DEPTH WIDTH WIDTH],
            ports: %w[data_o addr addr]
          },
          {
            name: "exception",
            parameters: [],
            ports: []
          }
        ]
      )

      expect(modules.map { |entry| entry[:name] }).to eq(%w[exception mem_prim])
      expect(modules.first[:source]).to include("class ImportedException < RHDL::Component")

      source = modules.last[:source]
      expect(source).to include("self._ports = []")
      expect(source).to include("self._generics = []")
      expect(source).to include("generic :DEPTH, default: 0")
      expect(source).to include("generic :WIDTH, default: 0")
      expect(source).to include("input :addr")
      expect(source).to include("input :data_o")
      expect(source).not_to include("def self.to_verilog")
    end

    it "keeps generated stub DSL declarations isolated across classes for dsl_super export" do
      modules = described_class.generate(
        signatures: [
          { name: "stub_a", parameters: [], ports: %w[clk port_a] },
          { name: "stub_b", parameters: [], ports: %w[clk port_b] }
        ]
      )

      namespace = Module.new
      modules.each do |entry|
        namespace.module_eval(entry.fetch(:source), "(generated_stub:#{entry.fetch(:name)})", 1)
      end

      stub_b = namespace.const_get("StubB")
      method = stub_b.method(:to_verilog)
      verilog = (method.super_method || method).call

      expect(verilog.scan(/\binput\b\s+clk\b/).length).to eq(1)
      expect(verilog).to include("input port_b")
      expect(verilog).not_to include("input port_a")
    end

    it "emits known primitive stubs with output port directions and deterministic behavior" do
      modules = described_class.generate(
        signatures: [
          {
            name: "altdpram",
            parameters: %w[width widthad width_byteena],
            ports: %w[data q wraddress rdaddress byteena inclock wren]
          }
        ]
      )

      altdpram = modules.fetch(0)
      expect(altdpram[:ports]).to include(
        { name: "q", direction: "output", width: "width" },
        { name: "data", direction: "input", width: "width" },
        { name: "wraddress", direction: "input", width: "widthad" },
        { name: "byteena", direction: "input", width: "width_byteena" }
      )

      source = altdpram.fetch(:source)
      expect(source).to include("output :q, width: :width")
      expect(source).to include("input :data, width: :width")
      expect(source).to include("assign :q, 0")
    end
  end
end
