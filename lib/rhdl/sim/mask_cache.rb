# frozen_string_literal: true

module RHDL
  module Sim
    # Pre-computed bit mask cache for common widths
    # Avoids repeated (1 << width) - 1 calculations in hot paths
    module MaskCache
      # Pre-compute masks for widths 0-64 (covers all common cases)
      MAX_CACHED_WIDTH = 64
      MASKS = Array.new(MAX_CACHED_WIDTH + 1) { |w| (1 << w) - 1 }.freeze

      class << self
        # Get mask for a given width
        # For widths <= MAX_CACHED_WIDTH, returns cached value
        # For larger widths, computes on demand
        def mask(width)
          if width <= MAX_CACHED_WIDTH
            MASKS[width]
          else
            (1 << width) - 1
          end
        end

        # Apply mask to a value
        def masked(value, width)
          value & mask(width)
        end
      end
    end
  end
end
