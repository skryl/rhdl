# frozen_string_literal: true

require File.expand_path("../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "T1-FPU/fpu_add_frac_dp.v",
  module_names: %w[fpu_add_frac_dp]
)
