# frozen_string_literal: true

module RHDL
  module DSL
    # If statement context
    class IfContext
      def initialize(if_stmt)
        @if_stmt = if_stmt
        @current_block = :then
      end

      def assign(target, value)
        stmt = SequentialAssignment.new(target, value)
        case @current_block
        when :then then @if_stmt.add_then(stmt)
        when :else then @if_stmt.add_else(stmt)
        end
      end

      def elsif_block(condition, &block)
        stmts = []
        ctx = BlockCollector.new(stmts)
        ctx.instance_eval(&block)
        @if_stmt.add_elsif(condition, stmts)
      end

      def else_block(&block)
        @current_block = :else
        instance_eval(&block)
        @current_block = :then
      end
    end
  end
end
