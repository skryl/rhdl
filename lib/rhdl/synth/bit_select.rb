# frozen_string_literal: true

module RHDL
  module Synth
    # Synthesis bit select
    # Handles both constant indices (becomes static slice) and
    # dynamic indices (becomes shift-and-mask operation)
    class BitSelect < Expr
      attr_reader :base, :index

      def initialize(base, index)
        @base = base
        @index = index
        super(1)
      end

      def to_ir
        if @index.is_a?(Integer)
          # Constant index - static bit slice
          RHDL::Codegen::IR::Slice.new(base: @base.to_ir, range: @index..@index, width: 1)
        else
          # Dynamic index - generate (base >> index) & 1
          # This implements runtime bit selection
          base_ir = @base.to_ir
          index_ir = @index.to_ir

          # (base >> index) & 1
          shifted = RHDL::Codegen::IR::BinaryOp.new(
            op: :>>,
            left: base_ir,
            right: index_ir,
            width: base_ir.width
          )

          # Mask to get just the lowest bit
          RHDL::Codegen::IR::BinaryOp.new(
            op: :&,
            left: shifted,
            right: RHDL::Codegen::IR::Literal.new(value: 1, width: 1),
            width: 1
          )
        end
      end
    end
  end
end
