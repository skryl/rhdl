# frozen_string_literal: true

require File.expand_path("../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "WB/wb_conbus_top.v",
  module_names: %w[wb_conbus_top]
)
