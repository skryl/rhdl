# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'pathname'

require_relative '../../../../examples/sparc64/utilities/import/system_importer'

RSpec.describe RHDL::Examples::SPARC64::Import::SystemImporter do
  def require_reference_tree!
    skip 'SPARC64 reference tree not available' unless Dir.exist?(described_class::DEFAULT_REFERENCE_ROOT)
    skip 'SPARC64 top source file not available' unless File.file?(described_class::DEFAULT_TOP_FILE)
  end

  def require_import_tool!
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_IMPORT_TOOL
    skip "#{tool} not available" unless HdlToolchain.which(tool)
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
  end

  def diagnostic_summary(result)
    lines = []
    lines.concat(Array(result.diagnostics)) if result.respond_to?(:diagnostics)
    Array(result.raise_diagnostics).each do |diag|
      if diag.respond_to?(:message)
        lines << "[#{diag.severity}]#{diag.respond_to?(:op) && diag.op ? " #{diag.op}:" : ''} #{diag.message}"
      else
        lines << diag.to_s
      end
    end
    lines.join("\n")
  end

  def new_importer(output_dir:, workspace_dir:, maintain_directory_structure: true, top: nil, top_file: nil)
    described_class.new(
      output_dir: output_dir,
      workspace_dir: workspace_dir,
      keep_workspace: true,
      clean_output: true,
      maintain_directory_structure: maintain_directory_structure,
      top: top || described_class::DEFAULT_TOP,
      top_file: top_file || described_class::DEFAULT_TOP_FILE,
      progress: ->(_msg) {}
    )
  end

  describe '#resolve_sources' do
    it 'builds a deterministic mixed-source manifest input set' do
      require_reference_tree!

      Dir.mktmpdir('sparc64_import_resolve') do |out_dir|
        Dir.mktmpdir('sparc64_import_resolve_ws') do |workspace|
          resolved = new_importer(output_dir: out_dir, workspace_dir: workspace).resolve_sources

          expect(resolved[:top][:name]).to eq('W1')
          expect(resolved[:top][:file]).to eq(File.expand_path('examples/sparc64/reference/Top/W1.v', Dir.pwd))
          expect(resolved[:files]).not_to be_empty
          expect(resolved[:closure_modules]).to include('W1', 'sparc', 'lsu', 'tlu', 'spu', 'fpu')
          expect(resolved[:module_files_by_name].fetch('W1')).to eq(File.expand_path('examples/sparc64/reference/Top/W1.v', Dir.pwd))
          expect(resolved[:module_files_by_name].fetch('sparc')).to eq(File.expand_path('examples/sparc64/reference/T1-CPU/rtl/sparc.v', Dir.pwd))
          expect(resolved[:module_files_by_name].fetch('bw_u1_buf_10x')).to eq(File.expand_path('examples/sparc64/reference/T1-common/u1/u1.V', Dir.pwd))
          expect(resolved[:files].all? { |entry| File.file?(entry[:path]) }).to be(true)
          expect(resolved[:include_dirs]).to include(
            File.expand_path('examples/sparc64/reference/T1-common/include', Dir.pwd)
          )
          expect(resolved[:files].map { |entry| entry[:path] }).not_to include(
            File.expand_path('examples/sparc64/reference/T1-common/srams/bw_r_tlb.v', Dir.pwd)
          )
          expect(resolved[:files].map { |entry| entry[:path] }).to include(
            File.expand_path('examples/sparc64/reference/T1-common/u1/u1.V', Dir.pwd)
          )
        end
      end
    end
  end

  describe '#run' do
    it 'imports the SPARC64 reference design with no diagnostics',
       timeout: ENV['TEST_ENV_NUMBER'] ? 900 : 480 do
      require_reference_tree!
      require_import_tool!

      Dir.mktmpdir('sparc64_import_out') do |out_dir|
        Dir.mktmpdir('sparc64_import_ws') do |workspace|
          result = new_importer(output_dir: out_dir, workspace_dir: workspace).run

          expect(result.success?).to be(true), diagnostic_summary(result)
          expect(Array(result.diagnostics)).to eq([])
          expect(Array(result.raise_diagnostics)).to eq([])
          expect(result.staged_root).to eq(File.join(workspace, 'mixed_sources'))
          expect(result.staged_top_file).to eq(File.join(workspace, 'mixed_sources', 'Top', 'W1.v'))
          expect(result.closure_modules).to include('W1', 'sparc', 'lsu', 'tlu', 'spu', 'fpu')
          expect(result.module_source_relpaths.fetch('W1')).to eq('Top/W1.v')
          expect(result.module_source_relpaths.fetch('sparc')).to eq('T1-CPU/rtl/sparc.v')
          expect(result.staged_source_paths_by_module.fetch('W1')).to eq(File.join(workspace, 'mixed_sources', 'Top', 'W1.v'))
          expect(result.staged_source_paths_by_module.fetch('sparc')).to eq(File.join(workspace, 'mixed_sources', 'T1-CPU/rtl/sparc.v'))
          expect(result.files_written).not_to be_empty
          relpaths = result.files_written.map do |path|
            Pathname.new(path).relative_path_from(Pathname.new(out_dir)).to_s
          end
          expect(relpaths).to include(
            'Top/w1.rb',
            'os2wb/s1_top.rb',
            'os2wb/os2wb_dual.rb',
            'WB/wb_conbus_top.rb',
            'T1-CPU/rtl/sparc.rb',
            'T1-CPU/lsu/lsu.rb',
            'T1-CPU/tlu/tlu.rb',
            'T1-CPU/spu/spu.rb',
            'T1-FPU/fpu.rb',
            'T1-common/common/dff_s.rb',
            'T1-common/common/dff_s_10.rb',
            'T1-common/u1/bw_u1_aoi21_4x.rb',
            'T1-common/srams/bw_r_dcd.rb'
          )
          expect(relpaths).not_to include(
            'w1.rb',
            's1_top.rb',
            'wb_conbus_top.rb',
            'sparc.rb',
            'dff_s.rb',
            'dff_s_10.rb',
            'bw_u1_aoi21_4x.rb',
            'bw_r_dcd.rb'
          )
          expect(File.file?(result.report_path)).to be(true)
          expect(File.file?(result.mlir_path)).to be(true)

          report = JSON.parse(File.read(result.report_path))
          expect(Array(report['import_diagnostics'])).to eq([])
          expect(Array(report['raise_diagnostics'])).to eq([])
        end
      end
    end
  end

  describe 'runtime primitive patching' do
    it 'rewrites dffrl_async for FPGA_SYN no-scan semantics' do
      Dir.mktmpdir('sparc64_runtime_patch') do |dir|
        path = File.join(dir, 'dffrl_async.rb')
        File.write(
          path,
          <<~RUBY
            # frozen_string_literal: true

            class DffrlAsync < RHDL::Sim::Component
              def self.verilog_module_name
                "dffrl_async"
              end
            end
          RUBY
        )

        diagnostics = []
        importer = new_importer(output_dir: dir, workspace_dir: dir)

        files_written = importer.send(
          :patch_generated_runtime_primitives,
          files_written: [path],
          diagnostics: diagnostics
        )

        patched = File.read(path)

        expect(files_written).to eq([path])
        expect(diagnostics).to include('SPARC64 runtime primitive patch applied for dffrl_async')
        expect(patched).to include('q <= din')
        expect(patched).to include('so <= 0')
        expect(patched).not_to include('q <= mux(se, si, din)')
        expect(patched).not_to include('so <= q')
      end
    end
  end

  describe 'source normalization' do
    it 'rewrites lsu_qctl1 pcx_pkt_src_sel into an acyclic form' do
      importer = new_importer(output_dir: Dir.pwd, workspace_dir: Dir.pwd)
      original = <<~VERILOG
        assign pcx_pkt_src_sel_tmp[2] = ~|{pcx_pkt_src_sel[3],pcx_pkt_src_sel[1:0]};
      VERILOG

      normalized = importer.send(
        :normalize_verilog_for_import,
        original,
        source_path: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-CPU', 'lsu', 'lsu_qctl1.v')
      )

      expect(normalized).to include(
        'assign pcx_pkt_src_sel_tmp[2] = ~rst_tri_en & ~|{pcx_pkt_src_sel_tmp[3], pcx_pkt_src_sel_tmp[1], pcx_pkt_src_sel_tmp[0]};'
      )
      expect(normalized).not_to include('pcx_pkt_src_sel[3],pcx_pkt_src_sel[1:0]')
    end

    it 'rewrites lsu_qctl1 fwd_int_fp_pcx_mx_sel into an acyclic form' do
      importer = new_importer(output_dir: Dir.pwd, workspace_dir: Dir.pwd)
      original = <<~VERILOG
        assign fwd_int_fp_pcx_mx_sel_tmp[0]= ~fwd_int_fp_pcx_mx_sel[1] & ~fwd_int_fp_pcx_mx_sel[2];
      VERILOG

      normalized = importer.send(
        :normalize_verilog_for_import,
        original,
        source_path: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-CPU', 'lsu', 'lsu_qctl1.v')
      )

      expect(normalized).to include(
        'assign fwd_int_fp_pcx_mx_sel_tmp[0] = ~rst_tri_en & ~fwd_int_fp_pcx_mx_sel_tmp[1] & ~fwd_int_fp_pcx_mx_sel_tmp[2];'
      )
      expect(normalized).not_to include('~fwd_int_fp_pcx_mx_sel[1] & ~fwd_int_fp_pcx_mx_sel[2]')
    end

    it 'rewrites sparc_tlu_dec64 into a direct decoder expression' do
      importer = new_importer(output_dir: Dir.pwd, workspace_dir: Dir.pwd)
      original = <<~VERILOG
        reg [63:0] out;
        integer i;

        always @ (in)
          begin
            for (i=0;i<64;i=i+1)
              begin
                if (i[5:0] == in[5:0])
                  out[i] = 1'b1;
                else
                  out[i] = 1'b0;
              end
          end
      VERILOG

      normalized = importer.send(
        :normalize_verilog_for_import,
        original,
        source_path: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-CPU', 'tlu', 'sparc_tlu_dec64.v')
      )

      expect(normalized).to include("assign out[63:0] = (64'h1 << in[5:0]);")
      expect(normalized).not_to include('always @ (in)')
      expect(normalized).not_to include("out[i] = 1'b1;")
    end

    it 'rewrites sparc_tlu_penc64 into an explicit priority chain' do
      importer = new_importer(output_dir: Dir.pwd, workspace_dir: Dir.pwd)
      original = <<~VERILOG
        reg [5:0] out;
        integer i;

        always @ (in)
        begin
          out = 6'b0;
          for (i=0;i<64;i=i+1)
            begin
              if (in[i])
                out[5:0] = i[5:0];
            end
        end
      VERILOG

      normalized = importer.send(
        :normalize_verilog_for_import,
        original,
        source_path: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-CPU', 'tlu', 'sparc_tlu_penc64.v')
      )

      aggregate_failures do
        expect(normalized).to include("assign out[5:0] = in[63] ? 6'd63")
        expect(normalized).to include(": (6'd0)")
        expect(normalized).not_to include('always @ (in)')
        expect(normalized).not_to include('out[5:0] = i[5:0];')
      end
    end

    it 'rewrites lsu_dc_parity_gen into explicit byte parity reductions' do
      importer = new_importer(output_dir: Dir.pwd, workspace_dir: Dir.pwd)
      original = <<~VERILOG
        reg [NUM - 1 : 0] parity;
        integer i;
        integer j;

        always @(data_in)
            for (i = 0; i <= NUM - 1 ; i = i + 1) begin
              parity[i] = 1'b0;
              for (j = WIDTH * i; j <= WIDTH * (i + 1) - 1 ; j = j + 1) begin
                parity[i] = parity[i] ^ data_in[j];
              end
            end

        assign parity_out[NUM - 1 : 0] = parity[NUM - 1 : 0];
      VERILOG

      normalized = importer.send(
        :normalize_verilog_for_import,
        original,
        source_path: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-CPU', 'lsu', 'lsu_dc_parity_gen.v')
      )

      aggregate_failures do
        expect(normalized).to include('assign parity_out[15:0] = {(^data_in[127:120]), (^data_in[119:112])')
        expect(normalized).to include('(^data_in[7:0])};')
        expect(normalized).not_to include('always @(data_in)')
        expect(normalized).not_to include('parity[i] = parity[i] ^ data_in[j];')
      end
    end
  end
end
