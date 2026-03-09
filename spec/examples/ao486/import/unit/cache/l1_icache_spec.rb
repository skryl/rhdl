# frozen_string_literal: true

require File.expand_path("../source_file_definition", __dir__)

RHDL::Examples::AO486::Unit::SourceFileDefinition.define!(
  source_relative_path: "cache/l1_icache.v",
  module_names: %w[l1_icache]
)
