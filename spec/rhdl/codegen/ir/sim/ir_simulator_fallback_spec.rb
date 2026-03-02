# frozen_string_literal: true

require "spec_helper"
require "json"
require "rhdl/codegen/ir/sim/ir_simulator"

RSpec.describe RHDL::Codegen::IR::IrSimulator do
  let(:ir_json) do
    {
      name: "fallback_test",
      ports: [
        { name: "a", direction: "in", width: 1 },
        { name: "y", direction: "out", width: 1 }
      ],
      nets: [],
      regs: [],
      assigns: [],
      processes: []
    }.to_json
  end

  it "falls back to Ruby simulator when native creation fails and fallback is enabled" do
    allow_any_instance_of(described_class).to receive(:select_backend).and_return(:interpreter)
    allow_any_instance_of(described_class).to receive(:configure_backend)
    allow_any_instance_of(described_class).to receive(:load_library)
    allow_any_instance_of(described_class).to receive(:create_simulator).and_raise(RuntimeError, "native parse error")

    simulator = described_class.new(ir_json, backend: :interpreter, allow_fallback: true)

    expect(simulator.backend).to eq(:ruby)
    expect(simulator.native?).to be(false)
  end

  it "raises native creation failures when fallback is disabled" do
    allow_any_instance_of(described_class).to receive(:select_backend).and_return(:interpreter)
    allow_any_instance_of(described_class).to receive(:configure_backend)
    allow_any_instance_of(described_class).to receive(:load_library)
    allow_any_instance_of(described_class).to receive(:create_simulator).and_raise(RuntimeError, "native parse error")

    expect do
      described_class.new(ir_json, backend: :interpreter, allow_fallback: false)
    end.to raise_error(RuntimeError, /native parse error/)
  end
end
