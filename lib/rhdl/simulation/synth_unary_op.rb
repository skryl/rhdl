# frozen_string_literal: true

module RHDL
  module HDL
    # Synthesis unary operation
    class SynthUnaryOp < SynthExpr
      attr_reader :op, :operand

      def initialize(op, operand, width)
        @op = op
        @operand = operand
        super(width)
      end

      def to_ir
        RHDL::Export::IR::UnaryOp.new(op: @op, operand: @operand.to_ir, width: @width)
      end
    end
  end
end
