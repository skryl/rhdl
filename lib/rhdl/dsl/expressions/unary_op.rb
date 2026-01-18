# frozen_string_literal: true

module RHDL
  module DSL
    # Unary operation expression
    class UnaryOp
      attr_reader :op, :operand

      def initialize(op, operand)
        @op = op
        @operand = operand
      end

      def to_verilog
        case op
        when :~ then "~#{operand.to_verilog}"
        else "#{op}#{operand.to_verilog}"
        end
      end
    end
  end
end
