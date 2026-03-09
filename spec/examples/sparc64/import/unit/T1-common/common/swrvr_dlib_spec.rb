# frozen_string_literal: true

require File.expand_path("../../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "T1-common/common/swrvr_dlib.v",
  module_names: %w[dp_buffer dp_mux2es dp_mux3ds dp_mux4ds]
)
