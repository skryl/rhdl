# frozen_string_literal: true

module RHDL
  module Synth
    # Synthesis mux (conditional)
    class Mux < Expr
      attr_reader :condition, :when_true, :when_false

      def initialize(condition, when_true, when_false, width)
        @condition = condition
        @when_true = when_true
        @when_false = when_false
        super(width)
      end

      def to_ir(cache = nil)
        memoize_ir(cache) do
          RHDL::Codegen::CIRCT::IR::Mux.new(
            condition: @condition.to_ir(cache),
            when_true: @when_true.to_ir(cache),
            when_false: @when_false.to_ir(cache),
            width: @width
          )
        end
      end
    end
  end
end
