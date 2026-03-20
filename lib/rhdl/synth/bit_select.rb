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

      def to_ir(cache = nil)
        memoize_ir(cache) do
          if @index.is_a?(Integer)
            RHDL::Codegen::CIRCT::IR::Slice.new(base: @base.to_ir(cache), range: @index..@index, width: 1)
          else
            base_ir = @base.to_ir(cache)
            index_ir = @index.to_ir(cache)

            shifted = RHDL::Codegen::CIRCT::IR::BinaryOp.new(
              op: :>>,
              left: base_ir,
              right: index_ir,
              width: base_ir.width
            )

            RHDL::Codegen::CIRCT::IR::BinaryOp.new(
              op: :&,
              left: shifted,
              right: RHDL::Codegen::CIRCT::IR::Literal.new(value: 1, width: 1),
              width: 1
            )
          end
        end
      end

      private

      def ir_cache_key
        [self.class, @base.send(:ir_cache_key), @index.is_a?(Integer) ? @index : @index.send(:ir_cache_key)]
      end
    end
  end
end
