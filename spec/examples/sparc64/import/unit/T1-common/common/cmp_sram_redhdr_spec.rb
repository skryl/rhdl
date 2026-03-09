# frozen_string_literal: true

require File.expand_path("../../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "T1-common/common/cmp_sram_redhdr.v",
  module_names: %w[cmp_sram_redhdr]
)
