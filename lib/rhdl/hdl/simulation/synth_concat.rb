# frozen_string_literal: true

module RHDL
  module HDL
    # Synthesis concatenation
    class SynthConcat < SynthExpr
      attr_reader :parts

      def initialize(parts, width)
        @parts = parts
        super(width)
      end

      def to_ir
        RHDL::Export::IR::Concat.new(parts: @parts.map(&:to_ir), width: @width)
      end
    end
  end
end
