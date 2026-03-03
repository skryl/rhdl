# frozen_string_literal: true

require "spec_helper"

require_relative "../../../../examples/ao486/utilities/runners/ir_runner"
require_relative "../../../../examples/ao486/utilities/runners/verilator_runner"

RSpec.describe "ao486 backend runner contract", :slow, :no_vendor_reimport do
  let(:cwd) { File.expand_path("../../../../", __dir__) }
  let(:out_dir) { File.expand_path("../../../../examples/ao486/hdl", __dir__) }
  let(:vendor_root) { File.expand_path("../../../../examples/ao486/hdl/vendor/source_hdl", __dir__) }
  let(:binary) { File.expand_path("../../../../examples/ao486/software/bin/01_add_ax_cx_and_store.bin", __dir__) }

  it "VerilatorRunner returns program trace keys for generated source" do
    skip "Verilator not available" unless HdlToolchain.verilator_available?

    runner = RHDL::Examples::AO486::VerilatorRunner.new(
      source_mode: :generated,
      out_dir: out_dir,
      vendor_root: vendor_root,
      cwd: cwd
    )
    result = runner.run_program(
      program_binary: binary,
      cycles: 256,
      data_check_addresses: [0x0000_0200]
    )

    expect(result.keys).to include("pc_sequence", "instruction_sequence", "memory_writes", "memory_contents")
    expect(Array(result["pc_sequence"])).not_to be_empty
  end

  it "IrRunner returns program trace keys" do
    runner = RHDL::Examples::AO486::IrRunner.new(
      out_dir: out_dir,
      vendor_root: vendor_root,
      cwd: cwd
    )
    result = runner.run_program(
      program_binary: binary,
      cycles: 256,
      data_check_addresses: [0x0000_0200]
    )

    expect(result.keys).to include("pc_sequence", "instruction_sequence", "memory_writes", "memory_contents")
    expect(Array(result["pc_sequence"])).not_to be_empty
  end
end
