# frozen_string_literal: true

require File.expand_path("../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "T1-FPU/fpu_rptr_macros.v",
  module_names: %w[fpu_bufrpt_grp32 fpu_bufrpt_grp64]
)
