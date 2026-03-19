# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../examples/sparc64/utilities/integration/staged_verilog_bundle'

RSpec.describe RHDL::Examples::SPARC64::Integration::StagedVerilogBundle do
  let(:cache_root) { Dir.mktmpdir('sparc64_staged_verilog_bundle_spec') }

  after do
    FileUtils.rm_rf(cache_root)
  end

  def expect_minimally_patched_bundle(result)
    expect(result.top_module).to eq('s1_top')
    expect(File).to exist(result.top_file)
    expect(result.source_files).not_to be_empty
    expect(result.verilator_args).to include('-DFPGA_SYN', '-DNO_SCAN')

    expect(described_class::MINIMAL_PATCHES_DIR).to be_a(String)
    expect(
      Dir.glob(File.join(described_class::MINIMAL_PATCHES_DIR, '*.patch')).map { |path| File.basename(path) }
    ).to eq([
              '0001-bridge-minimal-nonfast-boot.patch',
              '0007-reset-thread0-startup.patch'
            ])

    os2wb_dual_file = File.join(result.staged_root, 'os2wb', 'os2wb_dual.v')
    ifu_swl_file = File.join(result.staged_root, 'T1-CPU', 'ifu', 'sparc_ifu_swl.v')
    staged_irf_register_file = File.join(result.staged_root, 'T1-common', 'srams', 'bw_r_irf_register.v')
    staged_dcd_file = File.join(result.staged_root, 'T1-common', 'srams', 'bw_r_dcd.v')
    support_stubs_file = File.join(result.staged_root, '__rhdl_sparc64_hierarchy_stubs.v')
    bridge_patch_file = File.join(described_class::MINIMAL_PATCHES_DIR, '0001-bridge-minimal-nonfast-boot.patch')
    startup_patch_file = File.join(described_class::MINIMAL_PATCHES_DIR, '0007-reset-thread0-startup.patch')

    expect(File).to exist(os2wb_dual_file)
    expect(File).to exist(ifu_swl_file)
    expect(File).to exist(staged_irf_register_file)
    expect(File).to exist(staged_dcd_file)
    expect(File).to exist(support_stubs_file)

    expect(File.read(bridge_patch_file)).not_to include('diff --git a/os2wb/os2wb.v b/os2wb/os2wb.v')
    expect(File.read(startup_patch_file)).not_to include('assign dtu_fcl_nextthr_bf[3:0] = start_on_rst ? 4\'b0001 : fast_boot_nextthr_bf_raw[3:0];')

    os2wb_dual_source = File.read(os2wb_dual_file)
    expect(os2wb_dual_source).to include("`define MEM_SIZE         #{described_class::MINIMAL_MEM_SIZE}")
    expect(os2wb_dual_source).to include('`define TEST_DRAM        0')
    expect(os2wb_dual_source).to include("cpx_packet<=145'h1700000000000000000000000000000010001;")
    expect(os2wb_dual_source).to include('cpx_ready<=1;')

    ifu_swl_source = File.read(ifu_swl_file)
    expect(ifu_swl_source).to include('wire [8:0]    count;')
    expect(ifu_swl_source).to include("dffr_s #(9) thrrdy_ctr(.din ((count[8:0] == 9'd511) ? 9'd511 :")
    expect(ifu_swl_source).to include("assign start_thread = {3'b0, (count[8:0] == 9'd320)} |")
    expect(ifu_swl_source).not_to include('wire [3:0]    fast_boot_nextthr_bf_raw;')
    expect(ifu_swl_source).not_to include('wire          start_on_rst;')
    expect(ifu_swl_source).not_to include("assign start_on_rst = (count[8:0] == 9'd320);")
    expect(ifu_swl_source).not_to include('assign dtu_fcl_nextthr_bf[3:0] = start_on_rst ? 4\'b0001 : fast_boot_nextthr_bf_raw[3:0];')
    expect(ifu_swl_source).not_to include('assign proc0 =')
    expect(ifu_swl_source).not_to include('assign count_nxt[8:0] =')
    expect(ifu_swl_source).not_to include('.completion(completion[0] | start_on_rst),')
    expect(ifu_swl_source).not_to include('.schedule	(schedule[0] | start_on_rst),')
    expect(ifu_swl_source).not_to include('.switch_out(switch_out & ~start_on_rst),')
    expect(ifu_swl_source).not_to include('.stall     (all_stall[0] & ~start_on_rst),')

    expect(File.read(staged_irf_register_file)).to include('module bw_r_irf_register')
    expect(File.read(staged_dcd_file)).to include('module bw_r_dcd')

    support_stubs_source = File.read(support_stubs_file)
    expect(support_stubs_source).to include('module pcx_fifo(aclr, clock, data, rdreq, wrreq, empty, q);')
    expect(support_stubs_source).not_to include('module bw_r_irf_register(')
    expect(support_stubs_source).not_to include('module bw_r_dcd(')
  end

  it 'stages the SPARC64 s1_top mixed-source bundle with the minimal patch set by default', timeout: 120 do
    result = described_class.new(cache_root: cache_root, fast_boot: true).build
    expect_minimally_patched_bundle(result)
  end

  it 'reuses the cached staged bundle for identical inputs', timeout: 120 do
    first = described_class.new(cache_root: cache_root, fast_boot: true).build
    second = described_class.new(cache_root: cache_root, fast_boot: true).build

    expect(second.build_dir).to eq(first.build_dir)
    expect(second.top_file).to eq(first.top_file)
    expect(second.source_files).to eq(first.source_files)
  end

  it 'uses the same minimal patch set when fast_boot is false', timeout: 120 do
    result = described_class.new(cache_root: cache_root, fast_boot: false).build
    expect_minimally_patched_bundle(result)
  end

end
