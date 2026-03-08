# frozen_string_literal: true

require File.expand_path("../../source_file_definition", __dir__)

RHDL::Examples::SPARC64::Unit::SourceFileDefinition.define!(
  source_relative_path: "T1-common/common/swrvr_clib.v",
  module_names: %w[clken_buf dff_ns dff_s dffe_s dffr_s dffre_s dffrl_async dffrl_ns dffrle_ns dffrle_s mux2ds mux3ds mux4ds sink]
)
