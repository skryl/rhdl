# frozen_string_literal: true

module RHDL
  module Synth
    # Synthesis concatenation
    class Concat < Expr
      attr_reader :parts

      def initialize(parts, width)
        @parts = parts
        super(width)
      end

      def to_ir(cache = nil)
        memoize_ir(cache) do
          RHDL::Codegen::CIRCT::IR::Concat.new(parts: @parts.map { |part| part.to_ir(cache) }, width: @width)
        end
      end
    end
  end
end
