# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../examples/sparc64/utilities/integration/staged_verilog_bundle'

RSpec.describe RHDL::Examples::SPARC64::Integration::StagedVerilogBundle do
  let(:cache_root) { Dir.mktmpdir('sparc64_staged_verilog_bundle_spec') }

  after do
    FileUtils.rm_rf(cache_root)
  end

  it 'stages the SPARC64 s1_top mixed-source bundle with importer-managed fast-boot patching', timeout: 120 do
    result = described_class.new(cache_root: cache_root, fast_boot: true).build

    expect(result.top_module).to eq('s1_top')
    expect(File).to exist(result.top_file)
    expect(result.source_files).not_to be_empty
    expect(result.verilator_args).to include('-DFPGA_SYN')
    expect(described_class::FAST_BOOT_PATCHES_DIR).to be_a(String)
    expect(Dir.glob(File.join(described_class::FAST_BOOT_PATCHES_DIR, '*.patch'))).not_to be_empty

	    os2wb_file = File.join(result.build_dir, 'patched_reference', 'os2wb', 'os2wb.v')
	    os2wb_dual_file = File.join(result.staged_root, 'os2wb', 'os2wb_dual.v')
	    ifu_fdp_file = File.join(result.staged_root, 'T1-CPU', 'ifu', 'sparc_ifu_fdp.v')
	    ifu_swl_file = File.join(result.staged_root, 'T1-CPU', 'ifu', 'sparc_ifu_swl.v')
	    lsu_qctl1_file = File.join(result.staged_root, 'T1-CPU', 'lsu', 'lsu_qctl1.v')
	    sparc_rtl_file = File.join(result.staged_root, 'T1-CPU', 'rtl', 'sparc.v')
	    support_stubs_file = File.join(result.staged_root, '__rhdl_sparc64_hierarchy_stubs.v')

	    expect(File).to exist(os2wb_file)
	    expect(File).to exist(os2wb_dual_file)
	    expect(File).to exist(ifu_fdp_file)
	    expect(File).to exist(ifu_swl_file)
	    expect(File).to exist(lsu_qctl1_file)
	    expect(File).to exist(sparc_rtl_file)
	    expect(File).to exist(support_stubs_file)

    os2wb_source = File.read(os2wb_file)
    expect(os2wb_source).to include('`define TEST_DRAM        0')
    expect(os2wb_source).to include("`define MEM_SIZE         #{described_class::FAST_BOOT_MEM_SIZE}")
    expect(os2wb_source).to include('Fast boot must not inject the synthetic wakeup CPX packet')
    expect(os2wb_source).to include("cpx_packet<=145'b0;")
    expect(os2wb_source).to include('cpx_packet_1[127:0]<={wb_data_i,wb_data_i};')
    expect(os2wb_source).to include('cpx_packet_1[63:0]<=wb_data_i;')
    expect(os2wb_source).to include('cpx_packet_2[127:64]<=wb_data_i;')
    expect(os2wb_source).to include('cpx_packet_2[63:0]<=wb_data_i;')

    os2wb_dual_source = File.read(os2wb_dual_file)
    expect(os2wb_dual_source).to include('`define TEST_DRAM        0')
    expect(os2wb_dual_source).to include("`define MEM_SIZE         #{described_class::FAST_BOOT_MEM_SIZE}")
    expect(os2wb_dual_source).to include('if(ready)')
    expect(os2wb_dual_source).to include('Fast boot must not inject the synthetic wakeup CPX packet')
    expect(os2wb_dual_source).to include("cpx_packet<=145'b0;")
    expect(os2wb_dual_source).to include('cpx_ready<=0;')
    expect(os2wb_dual_source).to include('cpx_packet_1[127:0]<={wb_data_i,wb_data_i};')
    expect(os2wb_dual_source).to include('cpx_packet_1[63:0]<=wb_data_i;')
    expect(os2wb_dual_source).to include('cpx_packet_2[127:64]<=wb_data_i;')
    expect(os2wb_dual_source).to include('cpx_packet_2[63:0]<=wb_data_i;')

	    ifu_fdp_source = File.read(ifu_fdp_file)
	    expect(ifu_fdp_source).to include('nextpc_nosw_raw_bf')
	    expect(ifu_fdp_source).to include('dp_mux3ds #(49) pcp4_mux(.dout  (nextpc_nosw_raw_bf),')
	    expect(ifu_fdp_source).to include("49'h0_0000_0000_4000")

	    ifu_swl_source = File.read(ifu_swl_file)
	    expect(ifu_swl_source).to include('wire          start_on_rst;')
	    expect(ifu_swl_source).to include('dffr_s #(10) thrrdy_ctr')
	    expect(ifu_swl_source).to include('assign proc0 = (const_cpuid == 4\'b0000) ? 1\'b1 : 1\'b0;')
	    expect(ifu_swl_source).to include('assign start_thread = {3\'b0, start_on_rst} |')
	    expect(ifu_swl_source).to include('assign start_on_rst = (~count[9]) & proc0;')
	    expect(ifu_swl_source).to include('.stall     (all_stall[0] & ~start_on_rst),')

	    lsu_qctl1_source = File.read(lsu_qctl1_file)
	    expect(lsu_qctl1_source).to include('assign	lsu_ifu_pcxpkt_ack_d = ifu_lsu_pcxreq_d & ~pcx_req_squash_d1 ;')

	    sparc_rtl_source = File.read(sparc_rtl_file)
	    expect(sparc_rtl_source).to include('wire                 fast_boot_reset_vector;')
	    expect(sparc_rtl_source).to include("localparam [48:0]    FAST_BOOT_TRAPPC_W2  = 49'h0_0000_0000_4000;")
	    expect(sparc_rtl_source).to include("localparam [48:0]    FAST_BOOT_TRAPNPC_W2 = 49'h0_0000_0000_4004;")
	    expect(sparc_rtl_source).to include('.tlu_ifu_trapnpc_w2    (fast_boot_tlu_ifu_trapnpc_w2[48:0]),')
	    expect(sparc_rtl_source).to include('.tlu_ifu_trappc_w2     (fast_boot_tlu_ifu_trappc_w2[48:0]),')

	    support_stubs_source = File.read(support_stubs_file)
	    expect(support_stubs_source).to include('module pcx_fifo(aclr, clock, data, rdreq, wrreq, empty, q);')
	    expect(support_stubs_source).to include('output empty;')
	    expect(support_stubs_source).to include('output [129:0] q;')
	    expect(support_stubs_source).to include('reg [129:0] mem[0:3];')
	  end

  it 'reuses the cached staged bundle for identical inputs', timeout: 120 do
    first = described_class.new(cache_root: cache_root, fast_boot: true).build
    second = described_class.new(cache_root: cache_root, fast_boot: true).build

    expect(second.build_dir).to eq(first.build_dir)
    expect(second.top_file).to eq(first.top_file)
    expect(second.source_files).to eq(first.source_files)
  end
end
