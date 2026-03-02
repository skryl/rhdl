# frozen_string_literal: true

module RHDL
  module DSL
    # Unary operation expression
    class UnaryOp
      include ExpressionOperators

      attr_reader :op, :operand

      def initialize(op, operand)
        @op = op
        @operand = operand
      end

      def to_verilog
        rendered_operand = operand.respond_to?(:to_verilog) ? operand.to_verilog : operand.to_s
        if unary_operator_token?(op) && unary_operator_prefixed?(rendered_operand)
          "#{op}(#{rendered_operand})"
        else
          "#{op}#{rendered_operand}"
        end
      end

      private

      def unary_operator_token?(token)
        %i[~ & | ^ !].include?(token)
      end

      def unary_operator_prefixed?(text)
        value = text.to_s.lstrip
        return false if value.empty?

        %w[~ & | ^ !].any? { |prefix| value.start_with?(prefix) }
      end
    end
  end
end
