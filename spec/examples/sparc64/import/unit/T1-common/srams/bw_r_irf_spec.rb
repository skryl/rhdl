# frozen_string_literal: true

require File.expand_path("../../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "T1-common/srams/bw_r_irf.v",
  module_names: %w[bw_r_irf bw_r_irf_core]
)
