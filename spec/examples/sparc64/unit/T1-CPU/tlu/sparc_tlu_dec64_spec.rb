# frozen_string_literal: true

require File.expand_path("../../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "T1-CPU/tlu/sparc_tlu_dec64.v",
  module_names: %w[sparc_tlu_dec64]
)
