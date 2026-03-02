# frozen_string_literal: true

require "json"
require "spec_helper"
require "set"
require "tmpdir"

RSpec.describe "ao486 importer integration", :slow do
  PROGRAMS = [
    {
      name: "01_add_ax_cx_and_store",
      source: "01_add_ax_cx_and_store.asm",
      binary: "01_add_ax_cx_and_store.bin",
      data_check_addresses: [0x0000_0200]
    },
    {
      name: "02_add_with_secondary_store",
      source: "02_add_with_secondary_store.asm",
      binary: "02_add_with_secondary_store.bin",
      data_check_addresses: [0x0000_0200, 0x0000_0202, 0x0000_0204]
    },
    {
      name: "03_multi_reg_store",
      source: "03_multi_reg_store.asm",
      binary: "03_multi_reg_store.bin",
      data_check_addresses: [0x0000_0208, 0x0000_020A, 0x0000_020C]
    }
  ].freeze

  it "converts ao486 with blackbox stubs and writes a complete report" do
    source_root = File.expand_path("../../../../examples/ao486/reference/rtl/ao486", __dir__)
    skip "ao486 reference RTL is unavailable" unless Dir.exist?(source_root)

    Dir.mktmpdir do |dir|
      out_dir = File.join(dir, "ao486_import")
      result = RHDL::Import.project(
        out: out_dir,
        src: [source_root],
        dependency_resolution: "none",
        compile_unit_filter: "modules_only",
        missing_modules: "blackbox_stubs",
        no_check: true
      )

      expect(result).to be_success
      report = JSON.parse(File.read(result.report_path))
      normalized_report = assert_import_report_skeleton!(report, status: :success)
      summary = normalized_report.fetch("summary")

      expect(summary.fetch("converted_modules")).to be >= 40
      expect(summary.fetch("failed_modules")).to eq(0)
      expect(summary.fetch("blackboxes_generated")).to be >= 1
      expect(normalized_report.fetch("blackboxes_generated")).to include("cpu_export")
      expect(normalized_report.fetch("blackboxes_generated")).to include("l1_icache")

      module_files = Dir.glob(File.join(out_dir, "lib", "*", "modules", "**", "*.rb")).sort
      expect(module_files).not_to be_empty
      expected_module_files = (
        Array(normalized_report.dig("modules", "converted")) +
        Array(normalized_report.fetch("blackboxes_generated"))
      ).map { |name| "#{name.to_s.underscore}.rb" }.to_set
      actual_module_files = module_files.map { |path| File.basename(path) }.to_set
      expect(actual_module_files).to eq(expected_module_files)

      module_files.each do |module_file|
        source = File.read(module_file)
        expect(source).not_to match(/^\s*def\s+self\.to_verilog(?:_generated)?\b/)
        expect(source).not_to match(/^\s*def\s+self\.(sig|lit|mux|u)\b/)
        expect(source).not_to match(/\bRHDL::DSL::(?:SignalRef|Literal|TernaryOp|UnaryOp|BinaryOp|Concatenation|Replication)\b/)
      end
    end
  end

  it "runs ao486_trace with built-in harness when explicit trace inputs are not provided" do
    source_root = File.expand_path("../../../../examples/ao486/reference/rtl/ao486", __dir__)
    skip "ao486 reference RTL is unavailable" unless Dir.exist?(source_root)
    skip "Verilator not available" unless HdlToolchain.verilator_available?

    Dir.mktmpdir do |dir|
      out_dir = File.join(dir, "ao486_import_trace")
      result = RHDL::Import.project(
        out: out_dir,
        src: [source_root],
        dependency_resolution: "none",
        compile_unit_filter: "modules_only",
        missing_modules: "blackbox_stubs",
        top: ["ao486"],
        check_profile: "ao486_trace",
        trace_cycles: 64
      )

      expect(result).to be_success
      report = JSON.parse(File.read(result.report_path))
      normalized_report = assert_import_report_skeleton!(report, status: :success)
      summary = normalized_report.fetch("summary")

      expect(summary.fetch("checks_run")).to eq(1)
      expect(summary.fetch("checks_failed")).to eq(0)

      check_entry = normalized_report.fetch("checks").first
      expect(check_entry.fetch("profile")).to eq("ao486_trace")
      expect(check_entry.fetch("status")).to eq("pass")
      expect(check_entry.dig("trace_sources", "expected", "type")).to eq("ao486_harness")
      expect(check_entry.dig("trace_sources", "actual", "type")).to eq("ao486_harness")
      expect(check_entry.dig("summary", "events_compared")).to be >= 65
    end
  end

  it "runs ao486_trace with dsl_super converted export mode" do
    source_root = File.expand_path("../../../../examples/ao486/reference/rtl/ao486", __dir__)
    skip "ao486 reference RTL is unavailable" unless Dir.exist?(source_root)
    skip "Verilator not available" unless HdlToolchain.verilator_available?

    Dir.mktmpdir do |dir|
      out_dir = File.join(dir, "ao486_import_trace_dsl_super")
      result = RHDL::Import.project(
        out: out_dir,
        src: [source_root],
        dependency_resolution: "none",
        compile_unit_filter: "modules_only",
        missing_modules: "blackbox_stubs",
        top: ["ao486"],
        check_profile: "ao486_trace",
        trace_cycles: 64,
        trace_converted_export_mode: "dsl_super"
      )

      report = JSON.parse(File.read(result.report_path))
      unless result.success?
        summary = report.fetch("summary")
        check = Array(report["checks"]).first
        diagnostic = Array(report["diagnostics"]).first
        raise "dsl_super import failed: summary=#{summary.inspect} check=#{check.inspect} diagnostic=#{diagnostic.inspect} report=#{result.report_path}"
      end

      expect(result).to be_success
      normalized_report = assert_import_report_skeleton!(report, status: :success)
      summary = normalized_report.fetch("summary")

      expect(summary.fetch("checks_run")).to eq(1)
      expect(summary.fetch("checks_failed")).to eq(0)

      check_entry = normalized_report.fetch("checks").first
      expect(check_entry.fetch("profile")).to eq("ao486_trace")
      expect(check_entry.fetch("status")).to eq("pass")
      expect(check_entry.dig("summary", "events_compared")).to be >= 65
      expect(check_entry.dig("summary", "first_mismatch")).to be_nil
    end
  end

  it "runs ao486_trace_ir against converted IR simulation" do
    source_root = File.expand_path("../../../../examples/ao486/reference/rtl/ao486", __dir__)
    skip "ao486 reference RTL is unavailable" unless Dir.exist?(source_root)
    skip "Verilator not available" unless HdlToolchain.verilator_available?

    Dir.mktmpdir do |dir|
      out_dir = File.join(dir, "ao486_import_trace_ir")
      result = RHDL::Import.project(
        out: out_dir,
        src: [source_root],
        dependency_resolution: "none",
        compile_unit_filter: "modules_only",
        missing_modules: "blackbox_stubs",
        top: ["ao486"],
        check_profile: "ao486_trace_ir",
        trace_cycles: 64
      )

      expect(result).to be_success
      report = JSON.parse(File.read(result.report_path))
      normalized_report = assert_import_report_skeleton!(report, status: :success)
      summary = normalized_report.fetch("summary")

      expect(summary.fetch("checks_run")).to eq(1)
      expect(summary.fetch("checks_failed")).to eq(0)

      check_entry = normalized_report.fetch("checks").first
      expect(check_entry.fetch("profile")).to eq("ao486_trace_ir")
      expect(check_entry.fetch("status")).to eq("pass")
      expect(check_entry.dig("trace_sources", "expected", "type")).to eq("ao486_harness")
      expect(check_entry.dig("trace_sources", "actual", "type")).to eq("ao486_harness")
      expect(check_entry.dig("summary", "events_compared")).to be >= 65
      expect(check_entry.dig("summary", "first_mismatch")).to be_nil
    end
  end

  it "runs ao486_program_parity with sample reset-vector program across reference, generated verilog, and generated ir" do
    source_root = File.expand_path("../../../../examples/ao486/reference/rtl/ao486", __dir__)
    skip "ao486 reference RTL is unavailable" unless Dir.exist?(source_root)
    skip "Verilator not available" unless HdlToolchain.verilator_available?

    source_root_programs = File.expand_path("../../../../examples/ao486/software/source", __dir__)
    program_root = File.expand_path("../../../../examples/ao486/software/bin", __dir__)
    PROGRAMS.each do |program|
      source_path = File.join(source_root_programs, program.fetch(:source))
      expect(File.file?(source_path)).to be(true), "expected source program #{source_path}"

      program_binary = File.join(program_root, program.fetch(:binary))
      expect(File.file?(program_binary)).to be(true), "expected compiled binary #{program_binary}"

      Dir.mktmpdir do |dir|
        out_dir = File.join(dir, "ao486_import_program_parity_#{program.fetch(:name)}")
        result = RHDL::Import.project(
          out: out_dir,
          src: [source_root],
          dependency_resolution: "none",
          compile_unit_filter: "modules_only",
          missing_modules: "blackbox_stubs",
          top: ["ao486"],
          check_profile: "ao486_program_parity",
          trace_cycles: 256,
          verilog_tool: "verilator",
          program_binary: program_binary,
          program_binary_data_addresses: program.fetch(:data_check_addresses)
        )

        expect(result).to be_success
        report = JSON.parse(File.read(result.report_path))
        normalized_report = assert_import_report_skeleton!(report, status: :success)
        summary = normalized_report.fetch("summary")

        expect(summary.fetch("checks_run")).to eq(1)
        expect(summary.fetch("checks_failed")).to eq(0)

        check_entry = normalized_report.fetch("checks").first
        expect(check_entry.fetch("profile")).to eq("ao486_program_parity")
        expect(check_entry.fetch("status")).to eq("pass")
        expect(check_entry.dig("summary", "pc_events_compared")).to be > 0
        expect(check_entry.dig("summary", "instruction_events_compared")).to be > 0
        expect(check_entry.dig("summary", "memory_words_compared")).to be >= Array(program.fetch(:data_check_addresses)).length
        expect(check_entry.dig("summary", "first_mismatch")).to be_nil

        parity_report = JSON.parse(File.read(check_entry.fetch("report_path")))
        reference_trace = parity_report.dig("traces", "reference")
        generated_verilog_trace = parity_report.dig("traces", "generated_verilog")
        generated_ir_trace = parity_report.dig("traces", "generated_ir")

        reference_pc_sequence = Array(reference_trace.fetch("pc_sequence"))
        reference_instruction_sequence = Array(reference_trace.fetch("instruction_sequence"))
        expect(reference_pc_sequence.length).to be >= 3
        expect(reference_instruction_sequence.length).to be >= 3

        Array(program.fetch(:data_check_addresses)).each do |address|
          key = format("%08x", address)
          reference_data_word = reference_trace.fetch("memory_contents").fetch(key)
          expect(reference_data_word).to eq(generated_verilog_trace.fetch("memory_contents").fetch(key))
          expect(reference_data_word).to eq(generated_ir_trace.fetch("memory_contents").fetch(key))
        end
      end
    end
  end
end
