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

      def to_ir(cache = nil)
        memoize_ir(cache) do
          part_ir = @expr.to_ir(cache)
          parts = Array.new(@times, part_ir)
          RHDL::Codegen::CIRCT::IR::Concat.new(parts: parts, width: @width)
        end
      end
    end
  end
end
