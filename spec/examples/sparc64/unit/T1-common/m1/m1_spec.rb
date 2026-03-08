# frozen_string_literal: true

require File.expand_path("../../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "T1-common/m1/m1.V",
  module_names: %w[zzecc_exu_chkecc2 zzecc_sctag_ecc39]
)
