# frozen_string_literal: true

module RHDL
  module DSL
    # If statement context
    class IfContext
      def initialize(if_stmt)
        @if_stmt = if_stmt
        @current_block = :then
      end

      def assign(target, value, kind: :auto, nonblocking: nil)
        stmt = SequentialAssignment.new(target, value, kind: kind, nonblocking: nonblocking)
        case @current_block
        when :then then @if_stmt.add_then(stmt)
        when :else then @if_stmt.add_else(stmt)
        end
      end

      # Readable expression helpers used by importer-emitted branches.
      def sig(name, width: 1)
        SignalRef.new(name.to_sym, width: width)
      end

      def lit(value, width: nil, base: nil, signed: false)
        Literal.new(value, width: width, base: base, signed: signed)
      end

      def mux(condition, when_true, when_false)
        TernaryOp.new(condition, when_true, when_false)
      end

      def case_select(selector, cases:, default: 0)
        CaseSelect.new(selector, cases: cases, default: default)
      end

      def u(op, operand)
        UnaryOp.new(op.to_sym, operand)
      end

      def if_stmt(condition, &block)
        stmt = IfStatement.new(condition)
        ctx = IfContext.new(stmt)
        ctx.instance_eval(&block)
        case @current_block
        when :then then @if_stmt.add_then(stmt)
        when :else then @if_stmt.add_else(stmt)
        end
        stmt
      end

      def case_stmt(selector, qualifier: nil, &block)
        stmt = CaseStatement.new(selector, qualifier: qualifier)
        ctx = CaseContext.new(stmt)
        ctx.instance_eval(&block)
        case @current_block
        when :then then @if_stmt.add_then(stmt)
        when :else then @if_stmt.add_else(stmt)
        end
        stmt
      end

      def for_loop(var, range, &block)
        stmt = ForLoop.new(var, range)
        ctx = ProcessContext.new(stmt)
        ctx.instance_eval(&block)
        case @current_block
        when :then then @if_stmt.add_then(stmt)
        when :else then @if_stmt.add_else(stmt)
        end
        stmt
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
