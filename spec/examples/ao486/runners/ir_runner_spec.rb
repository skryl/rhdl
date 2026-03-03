# frozen_string_literal: true

require "json"
require "tmpdir"
require "spec_helper"

require_relative "../../../../examples/ao486/utilities/runners/ir_runner"

RSpec.describe RHDL::Examples::AO486::IrRunner do
  let(:root) { Dir.mktmpdir("ao486_ir_runner_spec") }
  let(:out_dir) { File.join(root, "hdl") }
  let(:vendor_root) { File.join(root, "vendor") }

  before do
    FileUtils.mkdir_p(File.join(out_dir, "lib"))
    FileUtils.mkdir_p(File.join(out_dir, "reports"))
    File.write(File.join(out_dir, "lib", "hdl.rb"), "# frozen_string_literal: true\n")
    File.write(File.join(out_dir, "reports", "import_report.json"), "{}\n")
  end

  after do
    FileUtils.remove_entry(root) if Dir.exist?(root)
  end

  describe "IR cache helpers" do
    it "writes and reloads cached IR JSON when fingerprint matches" do
      runner = described_class.new(out_dir: out_dir, vendor_root: vendor_root, cwd: root)
      allow(runner).to receive(:ir_cache_fingerprint).and_return("cache-fingerprint")
      allow(runner).to receive(:measure_step).and_wrap_original { |_m, _label, &block| block.call }

      payload = "{\"name\":\"ao486\"}"
      expect(runner.send(:write_cached_ir_json, payload)).to be(true)
      expect(runner.send(:load_cached_ir_json)).to eq(payload)
    end
  end

  describe "#simulator" do
    it "prefers cache path and skips rebuild when cached IR JSON is present" do
      runner = described_class.new(out_dir: out_dir, vendor_root: vendor_root, cwd: root)
      cached_ir_json = "{\"name\":\"ao486\"}"
      fake_sim = instance_double("IrSimulator", runner_kind: :ao486)

      allow(runner).to receive(:ir_cache_enabled?).and_return(true)
      allow(runner).to receive(:load_cached_ir_json).and_return(cached_ir_json)
      allow(runner).to receive(:build_simulator_from_ir_json).with(cached_ir_json).and_return(fake_sim)
      expect(RHDL::Import::Checks::Ao486TraceHarness).not_to receive(:new)

      expect(runner.send(:simulator)).to eq(fake_sim)
      expect(runner.send(:simulator)).to equal(fake_sim)
    end
  end
end
