# frozen_string_literal: true

require File.expand_path("../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "T1-FPU/fpu_rptr_min_global.v",
  module_names: %w[fpu_bufrpt_grp4 fpu_rptr_fp_cpx_grp16 fpu_rptr_inq fpu_rptr_pcx_fpio_grp16]
)
