# frozen_string_literal: true

module RHDL
  module Synth
    # Synthesis binary operation
    class BinaryOp < Expr
      attr_reader :op, :left, :right

      def initialize(op, left, right, width)
        @op = op
        @left = left
        @right = right
        super(width)
      end

      def to_ir
        # Handle the :le operator (<=) which we renamed to avoid conflict
        ir_op = @op == :le ? :<= : @op
        RHDL::Codegen::Behavior::IR::BinaryOp.new(
          op: ir_op,
          left: @left.to_ir,
          right: resize_ir(@right.to_ir, @left.width),
          width: @width
        )
      end

      private

      def resize_ir(ir_expr, target_width)
        return ir_expr if ir_expr.width == target_width
        RHDL::Codegen::Behavior::IR::Resize.new(expr: ir_expr, width: target_width)
      end
    end
  end
end
