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

  def new_importer(output_dir:, workspace_dir:, maintain_directory_structure: true, top: nil, top_file: nil, reference_root: nil,
                   patches_dir: nil)
    described_class.new(
      reference_root: reference_root || described_class::DEFAULT_REFERENCE_ROOT,
      output_dir: output_dir,
      workspace_dir: workspace_dir,
      keep_workspace: true,
      clean_output: true,
      maintain_directory_structure: maintain_directory_structure,
      top: top || described_class::DEFAULT_TOP,
      top_file: top_file || described_class::DEFAULT_TOP_FILE,
      patches_dir: patches_dir,
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
          expect(report.dig('artifacts', 'normalized_core_mlir_path')).to be_nil
        end
      end
    end
  end

  describe '#run_import_task' do
    it 'requires circt-verilog --top through the shared import task path' do
      fake_task_class = Class.new do
        class << self
          attr_accessor :last_options
        end

        def initialize(options)
          self.class.last_options = options
          @options = options
        end

        def run
          FileUtils.mkdir_p(@options.fetch(:out))
          File.write(File.join(@options.fetch(:out), 'generated_component.rb'), "# generated\n")
          File.write(@options.fetch(:report), "{}\n")
        end
      end

      Dir.mktmpdir('sparc64_import_task_out') do |out_dir|
        Dir.mktmpdir('sparc64_import_task_ws') do |workspace|
          report_path = File.join(out_dir, 'import_report.json')
          manifest_path = File.join(workspace, 'mixed.yml')
          File.write(manifest_path, "version: 1\n")

          importer = described_class.new(
            output_dir: out_dir,
            workspace_dir: workspace,
            keep_workspace: true,
            clean_output: false,
            top: 'W1',
            top_file: File.join(workspace, 'Top', 'W1.v'),
            import_task_class: fake_task_class,
            progress: ->(_msg) {}
          )

          result = importer.send(
            :run_import_task,
            mode: :mixed,
            mlir_path: File.join(out_dir, 'W1.core.mlir'),
            report_path: report_path,
            manifest_path: manifest_path
          )

          expect(result.fetch(:success)).to be(true)
          expect(fake_task_class.last_options.fetch(:require_verilog_import_top)).to be(true)
          expect(fake_task_class.last_options.fetch(:tool_args)).to include('--top=W1')
        end
      end
    end
  end

  describe '#write_import_source_bundle' do
    it 'emits a semantic bw_r_tlb_fpga hierarchy stub for the import path' do
      require_reference_tree!

      Dir.mktmpdir('sparc64_import_bundle_out') do |out_dir|
        Dir.mktmpdir('sparc64_import_bundle_ws') do |workspace|
          importer = new_importer(output_dir: out_dir, workspace_dir: workspace)
          resolved = importer.resolve_sources(workspace: workspace)
          bundle = importer.write_import_source_bundle(workspace: workspace, resolved: resolved)
          support_stubs_path = bundle.fetch(:tool_args).grep(/__rhdl_sparc64_hierarchy_stubs\.v\z/).fetch(0)
          support_stubs_source = File.read(support_stubs_path)

          aggregate_failures do
            expect(bundle.fetch(:tool_args)).to include('-DFPGA_SYN', '-DNO_SCAN')
            expect(support_stubs_source).to include('module bw_r_tlb_fpga(')
            expect(support_stubs_source).to include('output [39:10] tlb_pgnum_crit;')
            expect(support_stubs_source).to include('output [39:10] tlb_pgnum;')
            expect(support_stubs_source).to include('reg [30:0] va_tag_plus;')
            expect(support_stubs_source).to include('reg [29:0] vrtl_pgnum_m;')
            expect(support_stubs_source).to include('wire [26:0] tlb_cam_comp_key;')
            expect(support_stubs_source).to include('assign tlb_pgnum_crit = pgnum_m;')
            expect(support_stubs_source).to include('assign pgnum_m[29:18] = ~bypass_d ? phy_pgnum_m[29:18] : vrtl_pgnum_m[29:18];')
            expect(support_stubs_source).not_to include('assign tlb_pgnum_crit = virtual_pgnum;')
          end
        end
      end
    end

    it 'stages bw_r_irf_register as a real source instead of a hierarchy stub' do
      require_reference_tree!

      Dir.mktmpdir('sparc64_import_bundle_out') do |out_dir|
        Dir.mktmpdir('sparc64_import_bundle_ws') do |workspace|
          importer = new_importer(
            output_dir: out_dir,
            workspace_dir: workspace,
            top: 's1_top',
            top_file: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'os2wb', 's1_top.v'),
            patches_dir: File.expand_path('../../../../examples/sparc64/patches/fast_boot', __dir__)
          )
          resolved = importer.resolve_sources(workspace: workspace)
          bundle = importer.write_import_source_bundle(workspace: workspace, resolved: resolved)
          support_stubs_path = bundle.fetch(:tool_args).grep(/__rhdl_sparc64_hierarchy_stubs\.v\z/).fetch(0)
          support_stubs_source = File.read(support_stubs_path)
          staged_irf_register = File.join(bundle.fetch(:staged_root), 'T1-common', 'srams', 'bw_r_irf_register.v')

          aggregate_failures do
            expect(File.exist?(staged_irf_register)).to be(true)
            expect(bundle.fetch(:tool_args)).to include(staged_irf_register)
            expect(support_stubs_source).not_to include('module bw_r_irf_register(')
            expect(File.read(staged_irf_register)).to include('module bw_r_irf_register')
            expect(File.read(staged_irf_register)).to match(/output\s+\[71:0\]\s+rd_data;/)
          end
        end
      end
    end

    it 'stages bw_r_rf32x152b as a real source instead of a hierarchy stub' do
      require_reference_tree!

      Dir.mktmpdir('sparc64_import_bundle_out') do |out_dir|
        Dir.mktmpdir('sparc64_import_bundle_ws') do |workspace|
          importer = new_importer(
            output_dir: out_dir,
            workspace_dir: workspace,
            top: 's1_top',
            top_file: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'os2wb', 's1_top.v'),
            patches_dir: File.expand_path('../../../../examples/sparc64/patches/fast_boot', __dir__)
          )
          resolved = importer.resolve_sources(workspace: workspace)
          bundle = importer.write_import_source_bundle(workspace: workspace, resolved: resolved)
          support_stubs_path = bundle.fetch(:tool_args).grep(/__rhdl_sparc64_hierarchy_stubs\.v\z/).fetch(0)
          support_stubs_source = File.read(support_stubs_path)
          staged_dfq = File.join(bundle.fetch(:staged_root), 'T1-common', 'srams', 'bw_r_rf32x152b.v')

          aggregate_failures do
            expect(File.exist?(staged_dfq)).to be(true)
            expect(bundle.fetch(:tool_args)).to include(staged_dfq)
            expect(support_stubs_source).not_to include('module bw_r_rf32x152b(')
            expect(File.read(staged_dfq)).to include('module bw_r_rf32x152b')
            expect(File.read(staged_dfq)).to match(/output\s+\[151:0\]\s+dout\s*;/)
          end
        end
      end
    end

    it 'stages bw_r_dcd as a real source instead of a hierarchy stub' do
      require_reference_tree!

      Dir.mktmpdir('sparc64_import_bundle_out') do |out_dir|
        Dir.mktmpdir('sparc64_import_bundle_ws') do |workspace|
          importer = new_importer(
            output_dir: out_dir,
            workspace_dir: workspace,
            top: 's1_top',
            top_file: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'os2wb', 's1_top.v'),
            patches_dir: File.expand_path('../../../../examples/sparc64/patches/fast_boot', __dir__)
          )
          resolved = importer.resolve_sources(workspace: workspace)
          bundle = importer.write_import_source_bundle(workspace: workspace, resolved: resolved)
          support_stubs_path = bundle.fetch(:tool_args).grep(/__rhdl_sparc64_hierarchy_stubs\.v\z/).fetch(0)
          support_stubs_source = File.read(support_stubs_path)
          staged_dcd = File.join(bundle.fetch(:staged_root), 'T1-common', 'srams', 'bw_r_dcd.v')

          aggregate_failures do
            expect(File.exist?(staged_dcd)).to be(true)
            expect(bundle.fetch(:tool_args)).to include(staged_dcd)
            expect(support_stubs_source).not_to include('module bw_r_dcd(')
            expect(File.read(staged_dcd)).to include('module bw_r_dcd')
            expect(File.read(staged_dcd)).to match(/output\s+\[63:0\]\s+dcache_rdata_wb\s*;/)
          end
        end
      end
    end

  end

  describe 'patch directory support' do
    it 'rejects a missing patches_dir' do
      expect do
        described_class.new(output_dir: '/tmp/rhdl_sparc64_out', patches_dir: '/tmp/does_not_exist')
      end.to raise_error(ArgumentError, /patches_dir not found/)
    end

    it 'applies patches_dir before staging mixed-source inputs', timeout: 30 do
      Dir.mktmpdir('sparc64_patch_root') do |reference_root|
        Dir.mktmpdir('sparc64_patch_out') do |out_dir|
          Dir.mktmpdir('sparc64_patch_ws') do |workspace|
            FileUtils.mkdir_p(File.join(reference_root, 'Top'))
            FileUtils.mkdir_p(File.join(reference_root, 'T1-common', 'include'))

            File.write(
              File.join(reference_root, 'Top', 'W1.v'),
              <<~VERILOG
                module W1(
                  output wire out
                );
                  leaf leaf_inst(
                    .out(out)
                  );
                endmodule
              VERILOG
            )
            File.write(
              File.join(reference_root, 'leaf.v'),
              <<~VERILOG
                module leaf(
                  output wire out
                );
                  assign out = 1'b0;
                endmodule
              VERILOG
            )

            patches_dir = File.join(reference_root, 'patches')
            FileUtils.mkdir_p(patches_dir)
            File.write(
              File.join(patches_dir, '0001-leaf.patch'),
              <<~PATCH
                diff --git a/leaf.v b/leaf.v
                --- a/leaf.v
                +++ b/leaf.v
                @@ -1,5 +1,5 @@
                 module leaf(
                   output wire out
                 );
                -  assign out = 1'b0;
                +  assign out = 1'b1;
                 endmodule
              PATCH
            )

            importer = new_importer(
              reference_root: reference_root,
              output_dir: out_dir,
              workspace_dir: workspace,
              top: 'W1',
              top_file: File.join(reference_root, 'Top', 'W1.v'),
              patches_dir: patches_dir
            )

            resolved = importer.resolve_sources(workspace: workspace)
            bundle = importer.write_import_source_bundle(workspace: workspace, resolved: resolved)

            expect(resolved[:module_files_by_name].fetch('leaf')).to eq(File.join(workspace, 'patched_reference', 'leaf.v'))
            expect(File.read(File.join(bundle.fetch(:staged_root), 'leaf.v'))).to include("assign out = 1'b1;")
          end
        end
      end
    end

    it 'applies patches_dir when the importer workspace lives under the main repo root', timeout: 30 do
      Dir.mktmpdir('sparc64_patch_repo_root') do |reference_root|
        Dir.mktmpdir('sparc64_patch_repo_out') do |out_dir|
          repo_tmp_root = File.expand_path('../../../../tmp', __dir__)
          FileUtils.mkdir_p(repo_tmp_root)

          Dir.mktmpdir('sparc64_patch_repo_ws', repo_tmp_root) do |workspace|
            FileUtils.mkdir_p(File.join(reference_root, 'Top'))
            FileUtils.mkdir_p(File.join(reference_root, 'T1-common', 'include'))

            File.write(
              File.join(reference_root, 'Top', 'W1.v'),
              <<~VERILOG
                module W1(
                  output wire out
                );
                  leaf leaf_inst(
                    .out(out)
                  );
                endmodule
              VERILOG
            )
            File.write(
              File.join(reference_root, 'leaf.v'),
              <<~VERILOG
                module leaf(
                  output wire out
                );
                  assign out = 1'b0;
                endmodule
              VERILOG
            )

            patches_dir = File.join(reference_root, 'patches')
            FileUtils.mkdir_p(patches_dir)
            File.write(
              File.join(patches_dir, '0001-leaf.patch'),
              <<~PATCH
                diff --git a/leaf.v b/leaf.v
                --- a/leaf.v
                +++ b/leaf.v
                @@ -1,5 +1,5 @@
                 module leaf(
                   output wire out
                 );
                -  assign out = 1'b0;
                +  assign out = 1'b1;
                 endmodule
              PATCH
            )

            importer = new_importer(
              reference_root: reference_root,
              output_dir: out_dir,
              workspace_dir: workspace,
              top: 'W1',
              top_file: File.join(reference_root, 'Top', 'W1.v'),
              patches_dir: patches_dir
            )

            resolved = importer.resolve_sources(workspace: workspace)
            bundle = importer.write_import_source_bundle(workspace: workspace, resolved: resolved)

            expect(resolved[:module_files_by_name].fetch('leaf')).to eq(File.join(workspace, 'patched_reference', 'leaf.v'))
            expect(File.read(File.join(bundle.fetch(:staged_root), 'leaf.v'))).to include("assign out = 1'b1;")
          end
        end
      end
    end

    it 'keeps a patched top file on its relative path without staging a duplicate basename copy', timeout: 30 do
      Dir.mktmpdir('sparc64_patch_top_root') do |reference_root|
        Dir.mktmpdir('sparc64_patch_top_out') do |out_dir|
          Dir.mktmpdir('sparc64_patch_top_ws') do |workspace|
            FileUtils.mkdir_p(File.join(reference_root, 'os2wb'))
            FileUtils.mkdir_p(File.join(reference_root, 'patches'))

            File.write(
              File.join(reference_root, 'os2wb', 's1_top.v'),
              <<~VERILOG
                module s1_top(
                  output wire out
                );
                  assign out = 1'b0;
                endmodule
              VERILOG
            )

            File.write(
              File.join(reference_root, 'patches', '0001-top.patch'),
              <<~PATCH
                diff --git a/os2wb/s1_top.v b/os2wb/s1_top.v
                --- a/os2wb/s1_top.v
                +++ b/os2wb/s1_top.v
                @@ -1,5 +1,5 @@
                 module s1_top(
                   output wire out
                 );
                -  assign out = 1'b0;
                +  assign out = 1'b1;
                 endmodule
              PATCH
            )

            importer = new_importer(
              reference_root: reference_root,
              output_dir: out_dir,
              workspace_dir: workspace,
              top: 's1_top',
              top_file: File.join(reference_root, 'os2wb', 's1_top.v'),
              patches_dir: File.join(reference_root, 'patches')
            )

            resolved = importer.resolve_sources(workspace: workspace)
            bundle = importer.write_import_source_bundle(workspace: workspace, resolved: resolved)

            expect(resolved[:top][:file]).to eq(File.join(workspace, 'patched_reference', 'os2wb', 's1_top.v'))
            expect(bundle.fetch(:staged_top_file)).to eq(File.join(workspace, 'mixed_sources', 'os2wb', 's1_top.v'))
            expect(File.read(bundle.fetch(:staged_top_file))).to include("assign out = 1'b1;")
            expect(File).not_to exist(File.join(workspace, 'mixed_sources', 's1_top.v'))
            expect(
              bundle.fetch(:tool_args).count { |path| path.end_with?('/os2wb/s1_top.v') || path.end_with?('/s1_top.v') }
            ).to eq(0)
          end
        end
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
        expect(normalized).to include('genvar parity_idx;')
        expect(normalized).to include('for (parity_idx = 0; parity_idx < NUM; parity_idx = parity_idx + 1) begin : rhdl_parity_gen')
        expect(normalized).to include('assign parity_out[parity_idx] = ^data_in[(WIDTH * (parity_idx + 1)) - 1:WIDTH * parity_idx];')
        expect(normalized).not_to include('always @(data_in)')
        expect(normalized).not_to include('parity[i] = parity[i] ^ data_in[j];')
      end
    end

    it 'threads ifu_lsu_pcxpkt_e_b49 through the LSU fast-boot staging path' do
      importer = new_importer(output_dir: Dir.pwd, workspace_dir: Dir.pwd)
      lsu_source = File.read(File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-CPU', 'lsu', 'lsu.v'))
      lsu_qctl1_source = File.read(File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-CPU', 'lsu', 'lsu_qctl1.v'))

      normalized_lsu = importer.send(
        :normalize_verilog_for_import,
        lsu_source,
        source_path: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-CPU', 'lsu', 'lsu.v')
      )
      normalized_lsu_qctl1 = importer.send(
        :normalize_verilog_for_import,
        lsu_qctl1_source,
        source_path: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-CPU', 'lsu', 'lsu_qctl1.v')
      )

      aggregate_failures do
        expect(normalized_lsu).to include('.ifu_lsu_pcxpkt_e_b49   (ifu_lsu_pcxpkt_e[49]),')
        expect(normalized_lsu).to include('.ifu_lsu_pcxpkt_e_b49 (ifu_lsu_pcxpkt_e[49]),  // Templated')
        expect(normalized_lsu_qctl1).to include('lsu_ld_inst_vld_g, asi_internal_m, ifu_lsu_pcxpkt_e_b49, ifu_lsu_pcxpkt_e_b50,')
        expect(normalized_lsu_qctl1).to include("input\t\t\tifu_lsu_pcxpkt_e_b49 ;")
        expect(normalized_lsu_qctl1).to include('assign	lsu_ifu_pcxpkt_ack_d = imiss_pcx_rq_sel_d2 & ~pcx_req_squash_d1 ;  // Keep real LSU acceptance timing for fast boot')
      end
    end

    it 'adds Verilator public-flat annotations to staged IRF register thread flops' do
      importer = new_importer(output_dir: Dir.pwd, workspace_dir: Dir.pwd)
      original = File.read(File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_irf_register.v'))

      normalized = importer.send(
        :normalize_verilog_for_import,
        original,
        source_path: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_irf_register.v')
      )

      aggregate_failures do
        expect(normalized).to include('reg	[71:0]	reg_th0 /* verilator public_flat_rw */;')
        expect(normalized).to include('reg	[71:0]	reg_th1 /* verilator public_flat_rw */;')
        expect(normalized).to include('reg	[71:0]	reg_th2 /* verilator public_flat_rw */;')
        expect(normalized).to include('reg	[71:0]	reg_th3 /* verilator public_flat_rw */;')
      end
    end

    it 'strips inactive IRF preprocessor branches from bw_r_irf.v before import' do
      importer = new_importer(output_dir: Dir.pwd, workspace_dir: Dir.pwd)
      original = File.read(File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_irf.v'))

      normalized = importer.send(
        :normalize_verilog_for_import,
        original,
        source_path: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_irf.v')
      )

      aggregate_failures do
        expect(normalized).not_to include('`ifdef FPGA_SYN_IRF')
        expect(normalized).not_to include('`ifdef FPGA_SYN_1THREAD')
        expect(normalized.scan(/^module\s+bw_r_irf\b/).length).to eq(1)
        expect(normalized.scan(/^module\s+bw_r_irf_core\b/).length).to eq(1)
      end
    end

    it 'strips inactive IRF preprocessor branches from bw_r_irf_register.v before import' do
      importer = new_importer(output_dir: Dir.pwd, workspace_dir: Dir.pwd)
      original = File.read(File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_irf_register.v'))

      normalized = importer.send(
        :normalize_verilog_for_import,
        original,
        source_path: File.join(described_class::DEFAULT_REFERENCE_ROOT, 'T1-common', 'srams', 'bw_r_irf_register.v')
      )

      aggregate_failures do
        expect(normalized).not_to include('`ifdef FPGA_SYN_1THREAD')
        expect(normalized.scan(/^module\s+bw_r_irf_register\b/).length).to eq(1)
        expect(normalized).to include('input	[3:0]	wrens;')
        expect(normalized).to include('output	[71:0]	rd_data;')
      end
    end

    it 'uses hierarchical MLIR export for normalized core emission' do
      importer = new_importer(output_dir: Dir.pwd, workspace_dir: Dir.pwd)
      script = importer.send(:normalized_core_mlir_script)

      expect(script).to include('to_mlir_hierarchy')
      expect(script).to include('core_mlir_path')
      expect(script).not_to include('to_flat_circt_nodes')
    end
  end
end
