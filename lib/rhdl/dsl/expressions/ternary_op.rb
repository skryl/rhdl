# frozen_string_literal: true

module RHDL
  module DSL
    # Ternary conditional expression.
    class TernaryOp
      include ExpressionOperators

      attr_reader :condition, :when_true, :when_false

      def initialize(condition, when_true, when_false)
        @condition = condition
        @when_true = when_true
        @when_false = when_false
      end

      def to_verilog
        cond = condition.respond_to?(:to_verilog) ? condition.to_verilog : condition.to_s
        lhs = when_true.respond_to?(:to_verilog) ? when_true.to_verilog : when_true.to_s
        rhs = when_false.respond_to?(:to_verilog) ? when_false.to_verilog : when_false.to_s
        "(#{cond} ? #{lhs} : #{rhs})"
      end
    end
  end
end
