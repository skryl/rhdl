# frozen_string_literal: true

module RHDL
  module HDL
    # Synthesis replication
    class SynthReplicate < SynthExpr
      attr_reader :expr, :times

      def initialize(expr, times, width)
        @expr = expr
        @times = times
        super(width)
      end

      def to_ir
        parts = Array.new(@times) { @expr.to_ir }
        RHDL::Export::IR::Concat.new(parts: parts, width: @width)
      end
    end
  end
end
