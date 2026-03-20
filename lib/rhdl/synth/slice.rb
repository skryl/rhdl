# frozen_string_literal: true

module RHDL
  module Synth
    # Synthesis slice
    class Slice < Expr
      attr_reader :base, :range

      def initialize(base, range, width)
        @base = base
        @range = range
        super(width)
      end

      def to_ir(cache = nil)
        memoize_ir(cache) do
          RHDL::Codegen::CIRCT::IR::Slice.new(base: @base.to_ir(cache), range: @range, width: @width)
        end
      end

      private

      def ir_cache_key
        [self.class, @base.send(:ir_cache_key), @range.begin, @range.end, @width]
      end
    end
  end
end
