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

      def to_ir
        RHDL::Codegen::IR::Literal.new(value: @value, width: @width)
      end
    end
  end
end
