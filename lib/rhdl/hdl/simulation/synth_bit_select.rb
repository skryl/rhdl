# frozen_string_literal: true

module RHDL
  module HDL
    # Synthesis bit select
    class SynthBitSelect < SynthExpr
      attr_reader :base, :index

      def initialize(base, index)
        @base = base
        @index = index
        super(1)
      end

      def to_ir
        RHDL::Export::IR::Slice.new(base: @base.to_ir, range: @index..@index, width: 1)
      end
    end
  end
end
