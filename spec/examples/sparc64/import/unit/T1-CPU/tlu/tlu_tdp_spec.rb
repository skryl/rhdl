# frozen_string_literal: true

require File.expand_path("../../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "T1-CPU/tlu/tlu_tdp.v",
  module_names: %w[tlu_tdp]
)
