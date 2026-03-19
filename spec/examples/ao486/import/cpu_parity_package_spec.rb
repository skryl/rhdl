# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'

RSpec.describe 'AO486 default patch-series package' do
  def require_import_tool!
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
    skip "#{tool} not available" unless HdlToolchain.which(tool)
  end

  def run_importer(out_dir:, workspace:)
    RHDL::Examples::AO486::Import::CpuImporter.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true,
      maintain_directory_structure: false,
      patches_dir: RHDL::Examples::AO486::Import::CpuImporter::DEFAULT_PATCHES_ROOT
    ).run
  end

  def require_ir_backend!
    backend = AO486SpecSupport::IRBackendHelper.preferred_ir_backend
    skip 'IR compiler/JIT backend unavailable' unless backend

    backend
  end

  it 'builds a parity package that issues the reset-vector code fetch with cache disabled', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_parity_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_parity_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)
        imported = RHDL::Codegen.import_circt_mlir(File.read(result.normalized_core_mlir_path), strict: false, top: 'ao486')
        expect(imported.success?).to be(true), Array(imported.diagnostics).join("\n")

        flat = RHDL::Codegen::CIRCT::Flatten.to_flat_module(imported.modules, top: 'ao486')
        ir_json = RHDL::Sim::Native::IR.sim_json(flat, backend: backend)
        sim = RHDL::Sim::Native::IR::Simulator.new(ir_json, backend: backend)

        {
          'a20_enable' => 1,
          'cache_disable' => 1,
          'interrupt_do' => 0,
          'interrupt_vector' => 0,
          'avm_waitrequest' => 0,
          'avm_readdatavalid' => 0,
          'avm_readdata' => 0,
          'dma_address' => 0,
          'dma_16bit' => 0,
          'dma_write' => 0,
          'dma_writedata' => 0,
          'dma_read' => 0,
          'io_read_data' => 0,
          'io_read_done' => 0,
          'io_write_done' => 0
        }.each { |name, value| sim.poke(name, value) }

        sim.poke('clk', 0)
        sim.poke('rst_n', 0)
        sim.evaluate
        sim.poke('clk', 1)
        sim.tick

        saw_readcode = false
        saw_avalon = false
        readcode_address = nil
        avalon_address = nil
        4.times do
          sim.poke('clk', 0)
          sim.poke('rst_n', 1)
          sim.evaluate
          sim.poke('clk', 1)
          sim.poke('rst_n', 1)
          sim.tick

          if sim.peek('memory_inst__icache_inst__readcode_do') == 1
            saw_readcode = true
            readcode_address = sim.peek('memory_inst__icache_inst__readcode_address')
          end
          if sim.peek('avm_read') == 1
            saw_avalon = true
            avalon_address = sim.peek('avm_address')
          end
        end

        expect(saw_readcode).to be(true)
        expect(readcode_address).to eq(0xFFFF0)
        expect(saw_avalon).to be(true)
        expect(avalon_address).to eq(0x3FFFC)
      end
    end
  end
end
