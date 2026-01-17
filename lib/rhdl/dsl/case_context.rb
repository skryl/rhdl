# frozen_string_literal: true

module RHDL
  module DSL
    # Case statement context
    class CaseContext
      def initialize(case_stmt)
        @case_stmt = case_stmt
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
