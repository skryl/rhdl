# frozen_string_literal: true

module RHDL
  module Synth
    # Synthesis literal value
    class Literal < Expr
      attr_reader :value

      def initialize(value, width)
        @value = value
        super(width)
      end

      def to_ir(cache = nil)
        memoize_ir(cache) do
          RHDL::Codegen::CIRCT::IR::Literal.new(value: @value, width: @width)
        end
      end

      private

      def ir_cache_key
        [self.class, @value, @width]
      end
    end
  end
end
