# frozen_string_literal: true

require File.expand_path("../../source_file_definition", __dir__)

RHDL::Examples::AO486::Unit::SourceFileDefinition.define!(
  source_relative_path: "ao486/memory/tlb_memtype.v",
  module_names: %w[tlb_memtype]
)
