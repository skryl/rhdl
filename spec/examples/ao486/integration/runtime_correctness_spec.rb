# frozen_string_literal: true

require "spec_helper"

require "rhdl/import/checks/ao486_program_parity_harness"
require "rhdl/import/checks/ao486_trace_harness"
require "rhdl/import/checks/trace_comparator"
require_relative "../../../../examples/ao486/utilities/runners/headless_runner"

RSpec.describe "ao486 runtime correctness", :slow, :no_vendor_reimport do
  PROGRAMS = [
    {
      name: "01_add_ax_cx_and_store",
      binary: "01_add_ax_cx_and_store.bin",
      data_check_addresses: [0x0000_0200],
      cycles: 256
    },
    {
      name: "02_add_with_secondary_store",
      binary: "02_add_with_secondary_store.bin",
      data_check_addresses: [0x0000_0200, 0x0000_0202, 0x0000_0204],
      cycles: 256
    },
    {
      name: "03_multi_reg_store",
      binary: "03_multi_reg_store.bin",
      data_check_addresses: [0x0000_0208, 0x0000_020A, 0x0000_020C],
      cycles: 256
    },
    {
      name: "04_cellular_automaton",
      binary: "04_cellular_automaton.bin",
      data_check_addresses: [0x0000_0240, 0x0000_0242],
      cycles: 65_536
    },
    {
      name: "05_mandelbrot_fixedpoint",
      binary: "05_mandelbrot_fixedpoint.bin",
      data_check_addresses: [0x0000_0250, 0x0000_0252],
      cycles: 65_536
    },
    {
      name: "06_prime_sieve",
      binary: "06_prime_sieve.bin",
      data_check_addresses: [0x0000_0260, 0x0000_0262],
      cycles: 65_536
    }
  ].freeze

  let(:cwd) { File.expand_path("../../../../", __dir__) }
  let(:out_dir) { File.expand_path("../../../../examples/ao486/hdl", __dir__) }
  let(:source_root) { File.expand_path("../../../../examples/ao486/reference/rtl/ao486", __dir__) }
  let(:vendor_root) { File.expand_path("../../../../examples/ao486/hdl/vendor/source_hdl", __dir__) }
  let(:program_root) { File.expand_path("../../../../examples/ao486/software/bin", __dir__) }

  def require_converted_runtime_artifacts!(out_dir:)
    top_modules = Dir.glob(File.join(out_dir, "lib", "*", "modules", "**", "ao486.rb"))
    project_entrypoints = Dir.glob(File.join(out_dir, "lib", "*.rb"))
    return if top_modules.any? && project_entrypoints.any?

    skip "converted ao486 runtime artifacts are missing under #{out_dir}; run import once and reuse those outputs"
  end

  def capture_trace(mode:, converted_export_mode: nil)
    RHDL::Import::Checks::Ao486TraceHarness.capture(
      mode: mode,
      top: "ao486",
      out: out_dir,
      cycles: 64,
      source_root: source_root,
      converted_export_mode: converted_export_mode,
      cwd: cwd
    ).fetch("ao486")
  end

  def compare_trace!(expected:, actual:, label:)
    comparison = RHDL::Import::Checks::TraceComparator.compare(
      expected: expected,
      actual: actual
    )

    expect(comparison.fetch(:passed)).to be(true), "#{label} mismatch summary=#{comparison.fetch(:summary).inspect}"
    expect(comparison.dig(:summary, :events_compared)).to be >= 65
    expect(comparison.dig(:summary, :first_mismatch)).to be_nil
  end

  it "matches generated Verilog trace against vendor reference trace" do
    skip "ao486 reference RTL is unavailable" unless Dir.exist?(source_root)
    skip "Verilator not available" unless HdlToolchain.verilator_available?
    require_converted_runtime_artifacts!(out_dir: out_dir)

    reference = capture_trace(mode: "reference")
    generated_verilog = capture_trace(mode: "converted")

    compare_trace!(
      expected: reference,
      actual: generated_verilog,
      label: "generated Verilog trace"
    )
  end

  it "matches generated Verilog trace in dsl_super mode against vendor reference trace" do
    skip "ao486 reference RTL is unavailable" unless Dir.exist?(source_root)
    skip "Verilator not available" unless HdlToolchain.verilator_available?
    require_converted_runtime_artifacts!(out_dir: out_dir)

    reference = capture_trace(mode: "reference")
    generated_verilog = capture_trace(mode: "converted", converted_export_mode: "dsl_super")

    compare_trace!(
      expected: reference,
      actual: generated_verilog,
      label: "generated Verilog dsl_super trace"
    )
  end

  it "matches generated IR trace against vendor reference trace" do
    skip "ao486 reference RTL is unavailable" unless Dir.exist?(source_root)
    skip "Verilator not available" unless HdlToolchain.verilator_available?
    skip "IR compiler backend is unavailable" unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
    require_converted_runtime_artifacts!(out_dir: out_dir)

    reference = capture_trace(mode: "reference")
    generated_ir = capture_trace(mode: "converted_ir")

    compare_trace!(
      expected: reference,
      actual: generated_ir,
      label: "generated IR trace"
    )
  end

  it "runs sample reset-vector programs with multi-backend runtime parity", timeout: 420 do
    skip "ao486 reference RTL is unavailable" unless Dir.exist?(source_root)
    skip "Verilator not available" unless HdlToolchain.verilator_available?
    skip "Arcilator not available" unless HdlToolchain.arcilator_available?
    skip "IR compiler backend is unavailable" unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
    skip "IR interpreter backend is unavailable" unless RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
    skip "IR JIT backend is unavailable" unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
    require_converted_runtime_artifacts!(out_dir: out_dir)
    skip "ao486 vendor hdl tree is unavailable" unless Dir.exist?(vendor_root)

    vendor_runner = RHDL::Examples::AO486::HeadlessRunner.new(
      mode: :verilator,
      source_mode: :vendor,
      out_dir: out_dir,
      vendor_root: vendor_root,
      cwd: cwd
    )
    generated_verilog_runner = RHDL::Examples::AO486::HeadlessRunner.new(
      mode: :verilator,
      source_mode: :generated,
      out_dir: out_dir,
      vendor_root: vendor_root,
      cwd: cwd
    )
    generated_arcilator_runner = RHDL::Examples::AO486::HeadlessRunner.new(
      mode: :arcilator,
      out_dir: out_dir,
      vendor_root: vendor_root,
      cwd: cwd
    )
    generated_ir_runners = {
      compiler: RHDL::Examples::AO486::HeadlessRunner.new(
        mode: :ir,
        backend: :compiler,
        allow_fallback: false,
        out_dir: out_dir,
        vendor_root: vendor_root,
        cwd: cwd
      ),
      interpreter: RHDL::Examples::AO486::HeadlessRunner.new(
        mode: :ir,
        backend: :interpreter,
        allow_fallback: false,
        out_dir: out_dir,
        vendor_root: vendor_root,
        cwd: cwd
      ),
      jit: RHDL::Examples::AO486::HeadlessRunner.new(
        mode: :ir,
        backend: :jit,
        allow_fallback: false,
        out_dir: out_dir,
        vendor_root: vendor_root,
        cwd: cwd
      )
    }

    PROGRAMS.each do |program|
      program_binary = File.join(program_root, program.fetch(:binary))
      expect(File.file?(program_binary)).to be(true), "expected compiled binary #{program_binary}"

      comparison_harness = RHDL::Import::Checks::Ao486ProgramParityHarness.new(
        out: out_dir,
        top: "ao486",
        cycles: program.fetch(:cycles, 256),
        source_root: source_root,
        cwd: cwd,
        program_binary: program_binary,
        program_binary_data_addresses: program.fetch(:data_check_addresses),
        verilog_tool: "verilator"
      )

      reference = vendor_runner.run_program(
        program_binary: program_binary,
        cycles: program.fetch(:cycles, 256),
        data_check_addresses: program.fetch(:data_check_addresses)
      )
      generated_verilog = generated_verilog_runner.run_program(
        program_binary: program_binary,
        cycles: program.fetch(:cycles, 256),
        data_check_addresses: program.fetch(:data_check_addresses)
      )
      generated_backend_runs = {
        arcilator: generated_arcilator_runner.run_program(
          program_binary: program_binary,
          cycles: program.fetch(:cycles, 256),
          data_check_addresses: program.fetch(:data_check_addresses)
        )
      }
      generated_ir_runs = generated_ir_runners.transform_values do |runner|
        runner.run_program(
          program_binary: program_binary,
          cycles: program.fetch(:cycles, 256),
          data_check_addresses: program.fetch(:data_check_addresses)
        )
      end
      generated_backend_runs.merge!(generated_ir_runs)

      generated_backend_runs.each do |backend, generated_ir|
        comparison = comparison_harness.send(
          :compare_runs,
          reference: reference,
          generated_verilog: generated_verilog,
          generated_ir: generated_ir
        )
        expect(comparison.fetch(:mismatches)).to be_empty, "program parity failed for #{program.fetch(:name)} (backend=#{backend})"
        summary = comparison.fetch(:summary)
        expect(summary.fetch(:pc_events_compared)).to be > 0
        expect(summary.fetch(:instruction_events_compared)).to be > 0
        expect(summary.fetch(:memory_words_compared)).to be >= Array(program.fetch(:data_check_addresses)).length
        expect(summary.fetch(:first_mismatch)).to be_nil
      end

      compiler_trace = generated_ir_runs.fetch(:compiler)
      expect(generated_backend_runs.fetch(:arcilator).fetch("pc_sequence")).to eq(compiler_trace.fetch("pc_sequence"))
      expect(generated_ir_runs.fetch(:interpreter).fetch("pc_sequence")).to eq(compiler_trace.fetch("pc_sequence"))
      expect(generated_ir_runs.fetch(:jit).fetch("pc_sequence")).to eq(compiler_trace.fetch("pc_sequence"))
      expect(generated_backend_runs.fetch(:arcilator).fetch("instruction_sequence")).to eq(compiler_trace.fetch("instruction_sequence"))
      expect(generated_ir_runs.fetch(:interpreter).fetch("instruction_sequence")).to eq(compiler_trace.fetch("instruction_sequence"))
      expect(generated_ir_runs.fetch(:jit).fetch("instruction_sequence")).to eq(compiler_trace.fetch("instruction_sequence"))
    end
  end
end
