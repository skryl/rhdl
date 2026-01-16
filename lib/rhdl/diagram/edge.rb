# Diagram edge representation

module RHDL
  module Diagram
    class Edge
      attr_reader :from, :to, :label

      def initialize(from:, to:, label: nil)
        @from = from
        @to = to
        @label = label
      end

      def to_h
        {
          from: @from,
          to: @to,
          label: @label
        }
      end
    end
  end
end
