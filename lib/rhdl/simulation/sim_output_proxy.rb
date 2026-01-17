# frozen_string_literal: true

module RHDL
  module HDL
    # Proxy for output signals that captures assignments
    class SimOutputProxy < SimSignalProxy
      def initialize(name, wire, context)
        super(name, wire, :output, context)
      end

      # The <= operator for assignments
      def <=(expr)
        val = resolve(expr)
        mask = (1 << @width) - 1
        @context.record_assignment(@wire, val & mask)
      end

      private

      def resolve(other)
        case other
        when SimSignalProxy, SimOutputProxy, SimValueProxy
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
