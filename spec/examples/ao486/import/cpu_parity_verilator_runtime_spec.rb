# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_runtime'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_verilator_runtime'

RSpec.describe RHDL::Examples::AO486::Import::CpuParityVerilatorRuntime do
  VERILATOR_RESET_VECTOR_PROGRAM = [
    0x31, 0xC0, # xor ax, ax
    0x40, 0x90, # inc ax ; nop
    0xF4, 0x90  # hlt ; nop
  ].freeze

  def require_import_tool!
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
    skip "#{tool} not available" unless HdlToolchain.which(tool)
  end

  def run_importer(out_dir:, workspace:)
    RHDL::Examples::AO486::Import::CpuImporter.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true,
      maintain_directory_structure: false
    ).run
  end

  it 'matches JIT on the first reset-vector fetch words for the parity package', timeout: 600 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'firtool not available' unless HdlToolchain.which('firtool')
    skip 'verilator not available' unless HdlToolchain.verilator_available?
    skip 'IR JIT backend unavailable' unless RHDL::Sim::Native::IR::JIT_AVAILABLE

    Dir.mktmpdir('ao486_cpu_parity_verilator_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_parity_verilator_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        cleaned_mlir = File.read(result.normalized_core_mlir_path)

        jit_runtime = RHDL::Examples::AO486::Import::CpuParityRuntime.build_from_cleaned_mlir(cleaned_mlir)
        jit_runtime.load_bytes(described_class::RESET_VECTOR_PHYSICAL, VERILATOR_RESET_VECTOR_PROGRAM)
        jit_words = jit_runtime.run_fetch_words(max_cycles: 16)

        Dir.mktmpdir('ao486_cpu_parity_verilator_build') do |build_dir|
          verilator_runtime = described_class.build_from_cleaned_mlir(cleaned_mlir, work_dir: build_dir)
          verilator_runtime.load_bytes(described_class::RESET_VECTOR_PHYSICAL, VERILATOR_RESET_VECTOR_PROGRAM)
          verilator_words = verilator_runtime.run_fetch_words(max_cycles: 16)

          expect(verilator_words.first(2)).to eq(jit_words.first(2))
          expect(verilator_words.first(2)).to eq([0x9040_C031, 0x0000_90F4])
        end
      end
    end
  end
end
