# frozen_string_literal: true

module RHDL
  module Synth
    # Synthesis unary operation
    class UnaryOp < Expr
      attr_reader :op, :operand

      def initialize(op, operand, width)
        @op = op
        @operand = operand
        super(width)
      end

      def to_ir(cache = nil)
        memoize_ir(cache) do
          RHDL::Codegen::CIRCT::IR::UnaryOp.new(op: @op, operand: @operand.to_ir(cache), width: @width)
        end
      end
    end
  end
end
