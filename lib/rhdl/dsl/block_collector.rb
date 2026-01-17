# frozen_string_literal: true

module RHDL
  module DSL
    # Helper for collecting statements
    class BlockCollector
      def initialize(statements)
        @statements = statements
      end

      def assign(target, value)
        @statements << SequentialAssignment.new(target, value)
      end
    end
  end
end
