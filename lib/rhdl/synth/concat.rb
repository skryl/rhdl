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

      def to_ir
        RHDL::Codegen::Behavior::IR::Concat.new(parts: @parts.map(&:to_ir), width: @width)
      end
    end
  end
end
