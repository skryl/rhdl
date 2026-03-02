# frozen_string_literal: true

module RHDL
  module DSL
    # Context for process blocks
    class ProcessContext
      def initialize(process)
        @process = process
      end

      # Sequential assignment
      def assign(target, value, kind: :auto, nonblocking: nil)
        @process.add_statement(
          SequentialAssignment.new(target, value, kind: kind, nonblocking: nonblocking)
        )
      end

      # Readable expression helpers used by importer-emitted process bodies.
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

      # If statement
      def if_stmt(condition, &block)
        stmt = IfStatement.new(condition)
        ctx = IfContext.new(stmt)
        ctx.instance_eval(&block)
        @process.add_statement(stmt)
        stmt
      end

      # Case statement
      def case_stmt(selector, &block)
        stmt = CaseStatement.new(selector)
        ctx = CaseContext.new(stmt)
        ctx.instance_eval(&block)
        @process.add_statement(stmt)
        stmt
      end

      # For loop
      def for_loop(var, range, &block)
        stmt = ForLoop.new(var, range)
        ctx = ProcessContext.new(stmt)
        ctx.instance_eval(&block)
        @process.add_statement(stmt)
        stmt
      end

      # Rising edge check
      def rising_edge(signal)
        RisingEdge.new(signal)
      end

      # Falling edge check
      def falling_edge(signal)
        FallingEdge.new(signal)
      end
    end
  end
end
