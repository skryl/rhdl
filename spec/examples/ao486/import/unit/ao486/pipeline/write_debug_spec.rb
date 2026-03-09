# frozen_string_literal: true

require File.expand_path("../../source_file_definition", __dir__)

RHDL::Examples::AO486::Unit::SourceFileDefinition.define!(
  source_relative_path: "ao486/pipeline/write_debug.v",
  module_names: %w[write_debug]
)
