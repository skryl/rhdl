# frozen_string_literal: true

module RHDL
  module HDL
    # Synthesis slice
    class SynthSlice < SynthExpr
      attr_reader :base, :range

      def initialize(base, range, width)
        @base = base
        @range = range
        super(width)
      end

      def to_ir
        RHDL::Export::IR::Slice.new(base: @base.to_ir, range: @range, width: @width)
      end
    end
  end
end
