# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'
require_relative '../../../../examples/ao486/utilities/import/cpu_parity_runtime'

RSpec.describe RHDL::Examples::AO486::Import::CpuParityRuntime do
  JIT_RESET_VECTOR_PROGRAM = [
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

  it 'drives deterministic reset-vector fetch words on the parity package', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'IR JIT backend unavailable' unless RHDL::Sim::Native::IR::JIT_AVAILABLE

    Dir.mktmpdir('ao486_cpu_parity_runtime_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_parity_runtime_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        runtime = described_class.build_from_cleaned_mlir(File.read(result.normalized_core_mlir_path))

        runtime.load_bytes(described_class::RESET_VECTOR_PHYSICAL, JIT_RESET_VECTOR_PROGRAM)
        runtime.reset!

        fetched_words = []
        16.times do |cycle|
          runtime.step(cycle)
          next unless runtime.sim.peek('avm_readdatavalid') == 1

          fetched_words << runtime.sim.peek('avm_readdata')
        end

        expect(fetched_words.first(2)).to eq([0x9040_C031, 0x0000_90F4])
      end
    end
  end
end
