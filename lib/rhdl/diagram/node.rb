# Diagram node representation

module RHDL
  module Diagram
    class Node
      attr_reader :id, :kind, :label, :metadata

      def initialize(id:, kind:, label:, metadata: {})
        @id = id
        @kind = kind
        @label = label
        @metadata = metadata
      end

      def to_h
        {
          id: @id,
          kind: @kind,
          label: @label,
          metadata: @metadata
        }
      end
    end
  end
end
