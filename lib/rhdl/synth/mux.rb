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

      def to_ir
        RHDL::Codegen::Behavior::IR::Mux.new(
          condition: @condition.to_ir,
          when_true: @when_true.to_ir,
          when_false: @when_false.to_ir,
          width: @width
        )
      end
    end
  end
end
