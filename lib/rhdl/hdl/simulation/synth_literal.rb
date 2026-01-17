# frozen_string_literal: true

module RHDL
  module HDL
    # Synthesis literal value
    class SynthLiteral < SynthExpr
      attr_reader :value

      def initialize(value, width)
        @value = value
        super(width)
      end

      def to_ir
        RHDL::Export::IR::Literal.new(value: @value, width: @width)
      end
    end
  end
end
