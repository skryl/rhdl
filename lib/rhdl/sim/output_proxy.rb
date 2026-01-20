# frozen_string_literal: true

module RHDL
  module Sim
    # Proxy for output signals that captures assignments
    class OutputProxy < SignalProxy
      def initialize(name, wire, context)
        super(name, wire, :output, context)
      end

      # The <= operator for assignments
      def <=(expr)
        val = resolve(expr)
        @context.record_assignment(@wire, val & MaskCache.mask(@width))
      end

      private

      def resolve(other)
        case other
        when SignalProxy, OutputProxy, ValueProxy
          other.value
        when Integer
          other
        else
          other.respond_to?(:value) ? other.value : other.to_i
        end
      end
    end
  end
end
