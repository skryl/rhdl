# frozen_string_literal: true

require "json"
require "spec_helper"

require "rhdl/import/checks/ao486_program_parity_harness"
require "rhdl/import/checks/ao486_trace_harness"

RSpec.describe "ao486 IR backend runner support", :slow, :no_vendor_reimport do
  let(:cwd) { File.expand_path("../../../../", __dir__) }
  let(:out_dir) { File.expand_path("../../../../examples/ao486/hdl", __dir__) }
  let(:source_root) { File.expand_path("../../../../examples/ao486/reference/rtl/ao486", __dir__) }
  let(:vendor_root) { File.expand_path("../../../../examples/ao486/hdl/vendor/source_hdl", __dir__) }
  let(:program_binary) { File.expand_path("../../../../examples/ao486/software/bin/01_add_ax_cx_and_store.bin", __dir__) }

  def require_converted_runtime_artifacts!(out_dir:)
    top_modules = Dir.glob(File.join(out_dir, "lib", "*", "modules", "**", "ao486.rb"))
    project_entrypoints = Dir.glob(File.join(out_dir, "lib", "*.rb"))
    return if top_modules.any? && project_entrypoints.any?

    skip "converted ao486 runtime artifacts are missing under #{out_dir}; run import once and reuse those outputs"
  end

  def normalize_i64_compatible_json(value)
    i64_max = (1 << 63) - 1
    u64_max = (1 << 64) - 1

    case value
    when String
      text = value.lstrip
      return value unless text.start_with?("{", "[")

      parsed = JSON.parse(value, max_nesting: false)
      normalize_i64_compatible_json(parsed)
    when Hash
      value.each_with_object({}) do |(key, entry), memo|
        memo[key] = normalize_i64_compatible_json(entry)
      end
    when Array
      value.map { |entry| normalize_i64_compatible_json(entry) }
    when Integer
      return value unless value > i64_max && value <= u64_max

      value - (1 << 64)
    else
      value
    end
  end

  def build_normalized_ir_json
    helper = RHDL::Import::Checks::Ao486TraceHarness.new(
      mode: "converted_ir",
      top: "ao486",
      out: out_dir,
      cycles: 1,
      source_root: vendor_root,
      converted_export_mode: nil,
      cwd: cwd
    )
    components = helper.send(:load_converted_components)
    component_index = components.each_with_object({}) do |entry, memo|
      memo[entry.fetch(:source_module_name)] = entry
    end
    top_component = component_index.fetch("ao486")
    module_def = RHDL::Codegen::LIR::Lower.new(top_component.fetch(:component_class), top_name: "ao486").build
    flattened = helper.send(:flatten_ir_module, module_def: module_def, component_index: component_index)
    helper.send(:populate_missing_sensitivity_lists!, flattened)

    ir_json = RHDL::Codegen::IR::IRToJson.convert(flattened)
    normalized = normalize_i64_compatible_json(ir_json)
    normalized.is_a?(String) ? normalized : JSON.generate(normalized, max_nesting: false)
  end

  it "supports ao486 runner contract in interpreter, jit, and compiler backends", timeout: 240 do
    require_converted_runtime_artifacts!(out_dir: out_dir)
    skip "ao486 reference RTL is unavailable" unless Dir.exist?(source_root)
    skip "ao486 vendor hdl tree is unavailable" unless Dir.exist?(vendor_root)
    skip "program binary missing: #{program_binary}" unless File.file?(program_binary)
    skip "IR interpreter backend unavailable" unless RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
    skip "IR JIT backend unavailable" unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
    skip "IR compiler backend unavailable" unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE

    ir_json = build_normalized_ir_json
    harness = RHDL::Import::Checks::Ao486ProgramParityHarness.new(
      out: out_dir,
      top: "ao486",
      cycles: 256,
      source_root: source_root,
      cwd: cwd,
      program_binary: program_binary,
      program_binary_data_addresses: [0x0000_0200],
      verilog_tool: "verilator"
    )

    traces = {}
    %i[interpreter jit compiler].each do |backend|
      sim = RHDL::Codegen::IR::IrSimulator.new(ir_json, backend: backend, allow_fallback: false)
      expect(sim.runner_kind).to eq(:ao486)

      trace = harness.send(:run_ir_program, sim: sim)
      expect(Array(trace.fetch("pc_sequence", []))).not_to be_empty
      expect(Array(trace.fetch("instruction_sequence", []))).not_to be_empty
      traces[backend] = trace
    end

    expect(traces.fetch(:interpreter).fetch("pc_sequence")).to eq(traces.fetch(:compiler).fetch("pc_sequence"))
    expect(traces.fetch(:jit).fetch("pc_sequence")).to eq(traces.fetch(:compiler).fetch("pc_sequence"))
    expect(traces.fetch(:interpreter).fetch("instruction_sequence")).to eq(traces.fetch(:compiler).fetch("instruction_sequence"))
    expect(traces.fetch(:jit).fetch("instruction_sequence")).to eq(traces.fetch(:compiler).fetch("instruction_sequence"))
  end
end
