# frozen_string_literal: true

require File.expand_path("../../source_file_definition", __dir__)

RHDL::Examples::AO486::Unit::SourceFileDefinition.define!(
  source_relative_path: "ao486/memory/link_dcachewrite.v",
  module_names: %w[link_dcachewrite]
)
