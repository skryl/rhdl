# frozen_string_literal: true

require File.expand_path("../../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "T1-CPU/lsu/lsu_dc_parity_gen.v",
  module_names: %w[lsu_dc_parity_gen]
)
