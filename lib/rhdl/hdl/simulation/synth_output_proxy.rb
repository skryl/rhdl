# frozen_string_literal: true

module RHDL
  module HDL
    # Synthesis output proxy that captures assignments
    class SynthOutputProxy < SynthSignalProxy
      def initialize(name, width, context)
        super(name, width)
        @context = context
      end

      # The <= operator for assignments
      def <=(expr)
        synth_expr = expr.is_a?(SynthExpr) ? expr : SynthLiteral.new(expr, bit_width(expr))
        @context.record_assignment(@name, @width, synth_expr)
      end

      private

      def bit_width(value)
        return 1 if value == 0 || value == 1
        value.is_a?(Integer) ? [value.bit_length, 1].max : 1
      end
    end
  end
end
