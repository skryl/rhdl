# frozen_string_literal: true

require "spec_helper"

require_relative "../../../../examples/ao486/utilities/runners/headless_runner"

RSpec.describe "ao486 backend PC/instruction parity", :slow, :no_vendor_reimport do
  BACKEND_PARITY_PROGRAMS = [
    {
      name: "01_add_ax_cx_and_store",
      binary: "01_add_ax_cx_and_store.bin",
      data_check_addresses: [0x0000_0200],
      cycles: 128
    },
    {
      name: "02_add_with_secondary_store",
      binary: "02_add_with_secondary_store.bin",
      data_check_addresses: [0x0000_0200, 0x0000_0202, 0x0000_0204],
      cycles: 160
    },
    {
      name: "03_multi_reg_store",
      binary: "03_multi_reg_store.bin",
      data_check_addresses: [0x0000_0208, 0x0000_020A, 0x0000_020C],
      cycles: 192
    }
  ].freeze

  let(:cwd) { File.expand_path("../../../../", __dir__) }
  let(:out_dir) { File.expand_path("../../../../examples/ao486/hdl", __dir__) }
  let(:vendor_root) { File.expand_path("../../../../examples/ao486/hdl/vendor/source_hdl", __dir__) }
  let(:program_root) { File.expand_path("../../../../examples/ao486/software/bin", __dir__) }

  it "matches vendor Verilator PC/instruction traces across generated backends", timeout: 240 do
    expect(HdlToolchain.verilator_available?).to be_truthy, "Verilator is required for ao486 backend parity"
    expect(HdlToolchain.arcilator_available?).to be_truthy, "Arcilator is required for ao486 backend parity"
    expect(RHDL::Codegen::IR::IR_COMPILER_AVAILABLE).to be(true), "IR compiler backend is required for ao486 backend parity"

    vendor = RHDL::Examples::AO486::HeadlessRunner.new(
      mode: :verilator,
      source_mode: :vendor,
      out_dir: out_dir,
      vendor_root: vendor_root,
      cwd: cwd
    )
    generated_verilator = RHDL::Examples::AO486::HeadlessRunner.new(
      mode: :verilator,
      source_mode: :generated,
      out_dir: out_dir,
      vendor_root: vendor_root,
      cwd: cwd
    )
    generated_ir = RHDL::Examples::AO486::HeadlessRunner.new(
      mode: :ir,
      out_dir: out_dir,
      vendor_root: vendor_root,
      cwd: cwd
    )
    generated_arcilator = RHDL::Examples::AO486::HeadlessRunner.new(
      mode: :arcilator,
      out_dir: out_dir,
      vendor_root: vendor_root,
      cwd: cwd
    )

    BACKEND_PARITY_PROGRAMS.each do |program|
      binary = File.join(program_root, program.fetch(:binary))
      expect(File.file?(binary)).to be(true), "missing program binary #{binary}"

      vendor_trace = vendor.run_program(
        program_binary: binary,
        cycles: program.fetch(:cycles),
        data_check_addresses: program.fetch(:data_check_addresses)
      )
      verilator_trace = generated_verilator.run_program(
        program_binary: binary,
        cycles: program.fetch(:cycles),
        data_check_addresses: program.fetch(:data_check_addresses)
      )
      ir_trace = generated_ir.run_program(
        program_binary: binary,
        cycles: program.fetch(:cycles),
        data_check_addresses: program.fetch(:data_check_addresses)
      )
      arcilator_trace = generated_arcilator.run_program(
        program_binary: binary,
        cycles: program.fetch(:cycles),
        data_check_addresses: program.fetch(:data_check_addresses)
      )

      expect(verilator_trace.fetch("pc_sequence")).to eq(vendor_trace.fetch("pc_sequence")), "#{program.fetch(:name)} generated verilator PC mismatch"
      expect(ir_trace.fetch("pc_sequence")).to eq(vendor_trace.fetch("pc_sequence")), "#{program.fetch(:name)} generated IR PC mismatch"
      expect(arcilator_trace.fetch("pc_sequence")).to eq(vendor_trace.fetch("pc_sequence")), "#{program.fetch(:name)} generated arcilator PC mismatch"

      expect(verilator_trace.fetch("instruction_sequence")).to eq(vendor_trace.fetch("instruction_sequence")), "#{program.fetch(:name)} generated verilator instruction mismatch"
      expect(ir_trace.fetch("instruction_sequence")).to eq(vendor_trace.fetch("instruction_sequence")), "#{program.fetch(:name)} generated IR instruction mismatch"
      expect(arcilator_trace.fetch("instruction_sequence")).to eq(vendor_trace.fetch("instruction_sequence")), "#{program.fetch(:name)} generated arcilator instruction mismatch"
    end
  end
end
