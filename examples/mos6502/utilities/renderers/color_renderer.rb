# frozen_string_literal: true

# MOS6502 Color Renderer
# Wrapper around RHDL::Examples::Apple2::ColorRenderer for MOS6502 namespace compatibility
#
# This module provides backwards compatibility for code using RHDL::Examples::MOS6502::ColorRenderer
# while delegating all functionality to the shared RHDL::Examples::Apple2::ColorRenderer.
#
# Usage:
#   renderer = RHDL::Examples::MOS6502::ColorRenderer.new(chars_wide: 140, palette: :ntsc)
#   output = renderer.render(ram, base_addr: 0x2000)
#
# Options:
#   chars_wide:    Terminal width in characters (default: 140)
#   palette:       Color palette (:ntsc, :applewin, :kegs, :crt, :iigs, :virtual2)
#   monochrome:    Phosphor color (:green, :amber, :white, :cool, :warm) or nil
#   blend:         Enable color blending (default: false)
#   double_hires:  Enable double hi-res mode (default: false)

require_relative '../../../apple2/utilities/renderers/color_renderer'

module RHDL
  module Examples
    module MOS6502
      # Re-export the Apple2 ColorRenderer under the MOS6502 namespace
      # This maintains backwards compatibility while avoiding code duplication
      ColorRenderer = RHDL::Examples::Apple2::ColorRenderer

      # Also provide the legacy alias
      HiResColorRenderer = RHDL::Examples::Apple2::ColorRenderer
    end
  end
end
