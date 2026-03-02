# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "rhdl/import/checks/ao486_component_parity_harness"

RSpec.describe RHDL::Import::Checks::Ao486ComponentParityHarness do
  before do
    skip "Icarus Verilog not installed" unless HdlToolchain.iverilog_available?
  end

  def write_import_project(root:, operator:)
    out = File.join(root, "out")
    lib_dir = File.join(out, "lib")
    module_dir = File.join(lib_dir, "demo_project", "modules")
    FileUtils.mkdir_p(module_dir)

    File.write(
      File.join(out, "rhdl_import.yml"),
      <<~YAML
        ---
        project: demo_project
      YAML
    )

    File.write(
      File.join(lib_dir, "demo_project.rb"),
      <<~RUBY
        # frozen_string_literal: true

        require_relative "demo_project/modules/parity_and"
      RUBY
    )

    File.write(
      File.join(module_dir, "parity_and.rb"),
      <<~RUBY
        # frozen_string_literal: true

        class ParityAndImported < RHDL::Component
          include RHDL::DSL::Behavior
          include RHDL::DSL::Structure

          self._ports = []
          self._signals = []
          self._constants = []
          self._processes = []
          self._assignments = []
          self._instances = []
          self._generics = []

          # source_module: parity_and

          input :a
          input :b
          output :y

          assign :y, RHDL::DSL::BinaryOp.new(
            :#{operator},
            RHDL::DSL::SignalRef.new(:a, width: 1),
            RHDL::DSL::SignalRef.new(:b, width: 1)
          )
        end
      RUBY
    )

    out
  end

  def write_reference_sources(root:)
    source_root = File.join(root, "reference")
    FileUtils.mkdir_p(source_root)
    File.write(
      File.join(source_root, "parity_and.v"),
      <<~VERILOG
        module parity_and(
          input wire a,
          input wire b,
          output wire y
        );
          assign y = a & b;
        endmodule
      VERILOG
    )
    source_root
  end

  def write_sequential_import_project(root:)
    out = File.join(root, "out")
    lib_dir = File.join(out, "lib")
    module_dir = File.join(lib_dir, "demo_project", "modules")
    FileUtils.mkdir_p(module_dir)

    File.write(
      File.join(out, "rhdl_import.yml"),
      <<~YAML
        ---
        project: demo_project
      YAML
    )

    File.write(
      File.join(lib_dir, "demo_project.rb"),
      <<~RUBY
        # frozen_string_literal: true

        require_relative "demo_project/modules/parity_dff"
      RUBY
    )

    File.write(
      File.join(module_dir, "parity_dff.rb"),
      <<~RUBY
        # frozen_string_literal: true

        class ParityDffImported < RHDL::Component
          include RHDL::DSL::Behavior
          include RHDL::DSL::Structure

          self._ports = []
          self._signals = []
          self._constants = []
          self._processes = []
          self._assignments = []
          self._instances = []
          self._generics = []

          # source_module: parity_dff

          input :clk
          input :d
          output :q

          process :seq_logic, sensitivity: [{ edge: "posedge", signal: RHDL::DSL::SignalRef.new(:clk, width: 1) }], clocked: true do
            assign(:q, RHDL::DSL::SignalRef.new(:d, width: 1), kind: :nonblocking)
          end
        end
      RUBY
    )

    out
  end

  def write_reference_dff_source(root:)
    source_root = File.join(root, "reference")
    FileUtils.mkdir_p(source_root)
    File.write(
      File.join(source_root, "parity_dff.v"),
      <<~VERILOG
        module parity_dff(
          input wire clk,
          input wire d,
          output reg q
        );
          always @(posedge clk) begin
            q <= d;
          end
        endmodule
      VERILOG
    )
    source_root
  end

  it "passes three-way parity when converted behavior matches reference" do
    Dir.mktmpdir("ao486_component_parity_harness_spec") do |root|
      out = write_import_project(root: root, operator: "&")
      source_root = write_reference_sources(root: root)

      results = described_class.run(
        out: out,
        components: ["parity_and"],
        cycles: 8,
        seed: 123,
        source_root: source_root,
        cwd: Dir.pwd
      )

      expect(results.length).to eq(1)
      result = results.first
      expect(result[:component]).to eq("parity_and")
      expect(result[:status]).to eq("pass")
      expect(result.dig(:summary, :fail_count)).to eq(0)
      expect(result[:mismatches]).to eq([])
    end
  end

  it "fails three-way parity when converted behavior diverges" do
    Dir.mktmpdir("ao486_component_parity_harness_spec_fail") do |root|
      out = write_import_project(root: root, operator: "|")
      source_root = write_reference_sources(root: root)

      results = described_class.run(
        out: out,
        components: ["parity_and"],
        cycles: 8,
        seed: 123,
        source_root: source_root,
        cwd: Dir.pwd
      )

      expect(results.length).to eq(1)
      result = results.first
      expect(result[:component]).to eq("parity_and")
      expect(result[:status]).to eq("fail")
      expect(result.dig(:summary, :fail_count)).to be > 0
      mismatch = result[:mismatches].first
      expect(mismatch[:signal]).to eq("y")
      expect(mismatch).to include(:original, :generated_verilog, :generated_ir)
    end
  end

  it "matches three-way parity for clocked sequential behavior" do
    Dir.mktmpdir("ao486_component_parity_harness_spec_seq") do |root|
      out = write_sequential_import_project(root: root)
      source_root = write_reference_dff_source(root: root)

      results = described_class.run(
        out: out,
        components: ["parity_dff"],
        cycles: 8,
        seed: 123,
        source_root: source_root,
        cwd: Dir.pwd
      )

      expect(results.length).to eq(1)
      result = results.first
      expect(result[:component]).to eq("parity_dff")
      expect(result[:status]).to eq("pass")
      expect(result.dig(:summary, :fail_count)).to eq(0)
      expect(result[:mismatches]).to eq([])
    end
  end
end
