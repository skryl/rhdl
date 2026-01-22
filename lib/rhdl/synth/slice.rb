# frozen_string_literal: true

module RHDL
  module Synth
    # Synthesis slice
    class Slice < Expr
      attr_reader :base, :range

      def initialize(base, range, width)
        @base = base
        @range = range
        super(width)
      end

      def to_ir
        RHDL::Codegen::Verilog::IR::Slice.new(base: @base.to_ir, range: @range, width: @width)
      end
    end
  end
end
