# frozen_string_literal: true

module RHDL
  module DSL
    # Context for process blocks
    class ProcessContext
      def initialize(process)
        @process = process
      end

      # Sequential assignment
      def assign(target, value)
        @process.add_statement(SequentialAssignment.new(target, value))
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
