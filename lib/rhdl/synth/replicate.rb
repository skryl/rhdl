# frozen_string_literal: true

module RHDL
  module Synth
    # Synthesis replication
    class Replicate < Expr
      attr_reader :expr, :times

      def initialize(expr, times, width)
        @expr = expr
        @times = times
        super(width)
      end

      def to_ir
        parts = Array.new(@times) { @expr.to_ir }
        RHDL::Codegen::IR::Concat.new(parts: parts, width: @width)
      end
    end
  end
end
