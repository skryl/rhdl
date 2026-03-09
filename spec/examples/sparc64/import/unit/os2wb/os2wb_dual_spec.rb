# frozen_string_literal: true

require File.expand_path("../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "os2wb/os2wb_dual.v",
  module_names: %w[os2wb_dual]
)
