# frozen_string_literal: true

module RHDL
  module DSL
    # Binary operation expression
    class BinaryOp
      attr_reader :op, :left, :right

      VERILOG_OPS = {
        :+ => '+', :- => '-', :* => '*', :/ => '/',
        :& => '&', :| => '|', :^ => '^',
        :<< => '<<', :>> => '>>',
        :== => '==', :!= => '!=',
        :< => '<', :> => '>', :<= => '<=', :>= => '>='
      }

      def initialize(op, left, right)
        @op = op
        @left = left
        @right = right
      end

      def to_verilog
        l = left.respond_to?(:to_verilog) ? left.to_verilog : left.to_s
        r = right.respond_to?(:to_verilog) ? right.to_verilog : right.to_s
        "(#{l} #{VERILOG_OPS[op]} #{r})"
      end

      # Allow chaining
      def &(other); BinaryOp.new(:&, self, other); end
      def |(other); BinaryOp.new(:|, self, other); end
      def ^(other); BinaryOp.new(:^, self, other); end
    end
  end
end
