# frozen_string_literal: true

module RHDL
  module Synth
    # Synthesis bit select
    class BitSelect < Expr
      attr_reader :base, :index

      def initialize(base, index)
        @base = base
        @index = index
        super(1)
      end

      def to_ir
        RHDL::Codegen::Behavior::IR::Slice.new(base: @base.to_ir, range: @index..@index, width: 1)
      end
    end
  end
end
