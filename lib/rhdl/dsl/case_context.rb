# frozen_string_literal: true

module RHDL
  module DSL
    # Case statement context
    class CaseContext
      def initialize(case_stmt)
        @case_stmt = case_stmt
      end

      # Readable expression helpers used by importer-emitted case selectors.
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

      def when_value(value, &block)
        stmts = []
        ctx = BlockCollector.new(stmts)
        ctx.instance_eval(&block)
        @case_stmt.add_when(value, stmts)
      end

      def default(&block)
        stmts = []
        ctx = BlockCollector.new(stmts)
        ctx.instance_eval(&block)
        @case_stmt.add_default(stmts)
      end
    end
  end
end
