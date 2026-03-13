# frozen_string_literal: true

require 'spec_helper'

require_relative 'coverage_manifest'

RSpec.describe RHDL::Examples::SPARC64::Unit do
  it 'locks the current W1 mirrored coverage baseline' do
    expect(described_class::COVERED_SOURCE_FILE_COUNT).to eq(181)
    expect(described_class::COVERED_MODULE_COUNT).to eq(225)
  end

  it 'keeps representative source groupings locked' do
    expect(described_class::COVERED_SOURCE_FILES.fetch('Top/W1.v')).to eq(%w[W1])
    expect(described_class::COVERED_SOURCE_FILES.fetch('T1-common/common/swrvr_clib.v')).to eq(
      %w[clken_buf dff_ns dff_s dffe_s dffr_s dffre_s dffrl_async dffrl_ns dffrle_ns dffrle_s mux2ds mux3ds mux4ds sink]
    )
    expect(described_class::COVERED_SOURCE_FILES.fetch('T1-common/u1/u1.V')).to eq(
      %w[bw_u1_aoi21_4x bw_u1_aoi22_2x bw_u1_buf_10x bw_u1_buf_1x bw_u1_buf_20x bw_u1_buf_30x bw_u1_buf_5x bw_u1_inv_10x bw_u1_inv_15x bw_u1_inv_20x bw_u1_inv_30x bw_u1_inv_8x bw_u1_minbuf_5x bw_u1_muxi21_2x bw_u1_muxi21_6x bw_u1_nand2_10x bw_u1_nand2_15x bw_u1_nand2_2x bw_u1_nand2_4x bw_u1_nand3_4x bw_u1_nor3_8x bw_u1_soffm2_4x zsoffm2_prim]
    )
    expect(described_class::COVERED_SOURCE_FILES.fetch('T1-common/srams/bw_r_irf.v')).to eq(
      %w[bw_r_irf bw_r_irf_core]
    )
  end

  it 'maps each covered source file to a mirrored spec file' do
    unit_root = File.expand_path(__dir__)

    described_class::COVERED_SOURCE_FILES.each do |source_relative_path, module_names|
      spec_path = File.join(unit_root, described_class.spec_relative_path_for(source_relative_path))
      expect(File.file?(spec_path)).to be(true), "Missing mirrored spec for #{source_relative_path}: #{spec_path}"
      expect(module_names).to eq(module_names.uniq.sort)
      expect(module_names).not_to be_empty
    end
  end
end
