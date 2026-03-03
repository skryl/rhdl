# frozen_string_literal: true

require "spec_helper"

require_relative "../../../../examples/ao486/utilities/runners/headless_runner"

RSpec.describe RHDL::Examples::AO486::HeadlessRunner, :no_vendor_reimport do
  let(:common_options) do
    {
      out_dir: File.expand_path("../../../../examples/ao486/hdl", __dir__),
      vendor_root: File.expand_path("../../../../examples/ao486/hdl/vendor/source_hdl", __dir__),
      cwd: File.expand_path("../../../../", __dir__)
    }
  end

  it "builds an IR runner for mode :ir" do
    runner = described_class.new(mode: :ir, **common_options)
    expect(runner.runner).to be_a(RHDL::Examples::AO486::IrRunner)
  end

  it "builds a Verilator runner for mode :verilator" do
    runner = described_class.new(mode: :verilator, **common_options)
    expect(runner.runner).to be_a(RHDL::Examples::AO486::VerilatorRunner)
  end

  it "builds an Arcilator runner for mode :arcilator" do
    runner = described_class.new(mode: :arcilator, **common_options)
    expect(runner.runner).to be_a(RHDL::Examples::AO486::ArcilatorRunner)
  end

  it "reports live-cycle support only for backends that implement it" do
    ir_runner = described_class.new(mode: :ir, **common_options)
    verilator_runner = described_class.new(mode: :verilator, **common_options)
    arcilator_runner = described_class.new(mode: :arcilator, **common_options)

    expect(ir_runner.supports_live_cycles?).to eq(true)
    expect(verilator_runner.supports_live_cycles?).to eq(false)
    expect(arcilator_runner.supports_live_cycles?).to eq(false)
  end
end
