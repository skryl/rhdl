# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

require_relative '../../../../examples/ao486/utilities/import/cpu_importer'

RSpec.describe RHDL::Examples::AO486::Import::CpuImporter do
  def firtool_accepts?(mlir_text)
    return nil unless HdlToolchain.which('firtool')

    Dir.mktmpdir('ao486_cpu_import_firtool') do |dir|
      in_path = File.join(dir, 'input.mlir')
      out_path = File.join(dir, 'output.v')
      File.write(in_path, mlir_text)
      system('firtool', in_path, '--verilog', '-o', out_path, out: File::NULL, err: File::NULL)
    end
  end

  def require_import_tool!
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
    skip "#{tool} not available" unless HdlToolchain.which(tool)
  end

  def diagnostic_summary(result)
    lines = []
    diagnostics = result.respond_to?(:diagnostics) ? Array(result.diagnostics) : []
    lines.concat(diagnostics)
    extra_raise = result.respond_to?(:raise_diagnostics) ? Array(result.raise_diagnostics) : []
    extra_raise.each do |diag|
      lines << "[#{diag.severity}]#{diag.op ? " #{diag.op}:" : ''} #{diag.message}"
    end
    lines.join("\n")
  end

  def raise_runtime_component(cleaned_mlir, top:)
    raised = RHDL::Codegen.raise_circt_components(cleaned_mlir, top: top, strict: false)
    expect(raised.success?).to be(true), diagnostic_summary(raised)
    raised.components.fetch(top)
  end

  def run_importer(out_dir:, workspace:, maintain_directory_structure: true)
    described_class.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true,
      maintain_directory_structure: maintain_directory_structure
    ).run
  end

  def require_ir_backend!
    backend = AO486SpecSupport::IRBackendHelper.preferred_ir_backend
    skip 'IR compiler/JIT backend unavailable' unless backend

      backend
  end

  def write_unified_patch(path, relpath:, removal:, addition:)
    File.write(path, <<~PATCH)
      diff --git a/#{relpath} b/#{relpath}
      --- a/#{relpath}
      +++ b/#{relpath}
      @@ -1,2 +1,2 @@
      -#{removal}
      +#{addition}
       endmodule
    PATCH
  end

  it 'applies an opt-in patch series against the staged CPU source tree only' do
    skip 'patch not available' unless HdlToolchain.which('patch')

    Dir.mktmpdir('ao486_cpu_import_patch_root') do |root|
      rtl_root = File.join(root, 'rtl', 'ao486')
      FileUtils.mkdir_p(rtl_root)

      source_path = File.join(rtl_root, 'ao486.v')
      File.write(source_path, "module ao486;\nendmodule\n")

      patches_dir = File.join(root, 'patches')
      FileUtils.mkdir_p(patches_dir)
      write_unified_patch(
        File.join(patches_dir, '0001-ao486.patch'),
        relpath: 'ao486/ao486.v',
        removal: 'module ao486;',
        addition: 'module ao486; wire patched_cpu;'
      )

      workspace = File.join(root, 'workspace')
      importer = described_class.new(
        source_path: source_path,
        output_dir: File.join(root, 'out'),
        workspace_dir: workspace,
        keep_workspace: true,
        patches_dir: patches_dir
      )

      diagnostics = []
      command_log = []
      prepared_source = importer.send(:prepare_import_source_tree, workspace, diagnostics: diagnostics, command_log: command_log)
      expect(prepared_source[:success]).to be(true), diagnostics.join("\n")

      prepared = importer.send(:prepare_workspace, workspace, strategy: :stubbed)
      expect(File.read(source_path)).to eq("module ao486;\nendmodule\n")
      expect(File.read(prepared[:staged_system_path])).to include('patched_cpu')
      expect(prepared[:module_source_relpaths]).to include('ao486' => 'ao486/ao486.v')
      expect(command_log.any? { |cmd| cmd.include?('patch --batch -p1 -i') }).to be(true)
    end
  end

  it 'imports ao486.v through CIRCT and emits CPU artifacts needed for runtime parity', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_cpu_import_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_import_ws') do |workspace|
        result = run_importer(out_dir: out_dir, workspace: workspace)

        expect(result.strategy_requested).to eq(:tree)
        expect(result.strategy_used).to eq(:tree)
        expect(result.fallback_used).to be(false)
        expect(File.exist?(result.normalized_core_mlir_path)).to be(true)
        expect(result.files_written.map { |path| File.basename(path) }).to include('ao486.rb')
        expect(File.exist?(File.join(out_dir, 'ao486', 'ao486.rb'))).to be(true)
        expect(File.exist?(File.join(out_dir, 'cache', 'l1_icache.rb'))).to be(true)
        expect(File.exist?(File.join(out_dir, 'common', 'simple_mult.rb'))).to be(true)
      end
    end
  end

  it 'produces canonical CPU MLIR artifacts rooted at top ao486 and can raise runtime components', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_cpu_import_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_import_ws') do |workspace|
        result = run_importer(
          out_dir: out_dir,
          workspace: workspace,
          maintain_directory_structure: false
        )

        expect(File.basename(result.normalized_core_mlir_path)).to eq('ao486.tree.normalized.core.mlir')
        normalized = File.read(result.normalized_core_mlir_path)
        expect(normalized).to include('hw.module @ao486')
        expect(normalized).not_to include('llhd.')
        expect(normalized).to include('hw.array_get')
        expect(File.read(File.join(workspace, 'ao486.v'))).to include('`timescale 1ns/1ps')

        raised = RHDL::Codegen.raise_circt_components(normalized, top: 'ao486', strict: false)
        expect(raised.success?).to be(true), diagnostic_summary(raised)
        expect(raised.components).to include('ao486')

        firtool_result = firtool_accepts?(normalized)
        expect(firtool_result).not_to eq(false)
      end
    end
  end

  it 'builds a flattened IR runtime from the cleaned imported CPU modules', timeout: 240 do
    require_import_tool!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    backend = require_ir_backend!

    Dir.mktmpdir('ao486_cpu_import_out') do |out_dir|
      Dir.mktmpdir('ao486_cpu_import_ws') do |workspace|
        result = run_importer(
          out_dir: out_dir,
          workspace: workspace,
          maintain_directory_structure: false
        )

        cleaned = File.read(result.normalized_core_mlir_path)
        flat = raise_runtime_component(cleaned, top: 'ao486').to_flat_circt_nodes(top_name: 'ao486')
        runtime_mod = RHDL::Codegen::CIRCT::RuntimeJSON.normalize_modules_for_runtime([flat]).first
        duplicate_runtime_assigns = runtime_mod.assigns.group_by { |assign| assign.target.to_s }
                                              .select { |_target, assigns| assigns.length > 1 }
        expect(duplicate_runtime_assigns).to be_empty,
          "duplicate runtime assign targets: #{duplicate_runtime_assigns.keys.first(10).join(', ')}"

        ir_json = RHDL::Sim::Native::IR.sim_json(flat, backend: backend)
        sim = RHDL::Sim::Native::IR::Simulator.new(ir_json, backend: backend)

        expect(sim.has_signal?('clk')).to be(true)
        expect(sim.has_signal?('rst_n')).to be(true)
        expect(sim.has_signal?('avm_read')).to be(true)
        expect(sim.has_signal?('avm_address')).to be(true)
        expect(sim.has_signal?('io_read_do')).to be(true)
        expect(sim.has_signal?('io_write_do')).to be(true)

        {
          'a20_enable' => 1,
          'cache_disable' => 0,
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

        expect(sim.peek('pipeline_inst__decode_inst__eip')).to eq(0xFFF0)
        expect(sim.peek('memory_inst__prefetch_inst__prefetch_address')).to eq(0xFFFF0)
        expect(sim.peek('memory_inst__prefetch_inst__prefetch_length')).to eq(16)

        sim.poke('clk', 0)
        sim.poke('rst_n', 1)
        sim.evaluate
        sim.poke('clk', 1)
        sim.poke('rst_n', 1)
        sim.tick
        expect(sim.peek('memory_inst__tlb_inst__tlbcode_do')).to eq(1)
        expect(sim.peek('memory_inst__prefetch_control_inst__tlbcode_do')).to eq(1)
        expect(sim.peek('memory_inst__prefetch_control_inst__icacheread_do')).to eq(1)

        sim.poke('clk', 0)
        sim.poke('rst_n', 1)
        sim.evaluate
        sim.poke('clk', 1)
        sim.poke('rst_n', 1)
        sim.tick

        expect(sim.peek('memory_inst__tlb_inst__tlbcode_do')).to eq(0)
        expect(sim.peek('memory_inst__prefetch_control_inst__tlbcode_do')).to eq(0)
        expect(sim.peek('memory_inst__prefetch_control_inst__icacheread_do')).to eq(1)
      end
    end
  end
end
