# frozen_string_literal: true

module RHDL
  module DSL
    # Helper for collecting statements
    class BlockCollector
      def initialize(statements)
        @statements = statements
      end

      def assign(target, value, kind: :auto, nonblocking: nil)
        @statements << SequentialAssignment.new(target, value, kind: kind, nonblocking: nonblocking)
      end

      # Readable expression helpers used by importer-emitted blocks.
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
        @statements << stmt
        stmt
      end

      def case_stmt(selector, qualifier: nil, &block)
        stmt = CaseStatement.new(selector, qualifier: qualifier)
        ctx = CaseContext.new(stmt)
        ctx.instance_eval(&block)
        @statements << stmt
        stmt
      end

      def for_loop(var, range, &block)
        stmt = ForLoop.new(var, range)
        ctx = ProcessContext.new(stmt)
        ctx.instance_eval(&block)
        @statements << stmt
        stmt
      end
    end
  end
end
