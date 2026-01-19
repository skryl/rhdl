# frozen_string_literal: true

# HDL Debug Features - Component Specs
#
# This file loads all individual debug component spec files.
# Each component has its own spec file in the debug/ directory.

require_relative 'debug/signal_probe_spec'
require_relative 'debug/breakpoint_spec'
require_relative 'debug/watchpoint_spec'
require_relative 'debug/waveform_capture_spec'
require_relative 'debug/debug_simulator_spec'
