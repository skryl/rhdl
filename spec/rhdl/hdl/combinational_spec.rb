# frozen_string_literal: true

# HDL Combinational Components - Individual Spec Files
#
# This file requires all individual combinational component spec files.
# Each component has its own dedicated spec file in the combinational/ directory.

require_relative 'combinational/mux2_spec'
require_relative 'combinational/mux4_spec'
require_relative 'combinational/mux8_spec'
require_relative 'combinational/demux2_spec'
require_relative 'combinational/demux4_spec'
require_relative 'combinational/decoder2to4_spec'
require_relative 'combinational/decoder3to8_spec'
require_relative 'combinational/encoder4to2_spec'
require_relative 'combinational/encoder8to3_spec'
require_relative 'combinational/barrel_shifter_spec'
require_relative 'combinational/bit_reverse_spec'
require_relative 'combinational/zero_detect_spec'
require_relative 'combinational/zero_extend_spec'
require_relative 'combinational/sign_extend_spec'
require_relative 'combinational/lz_count_spec'
require_relative 'combinational/pop_count_spec'
