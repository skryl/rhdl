# frozen_string_literal: true

module RHDL
  module DSL
    # Bit slice expression
    class BitSlice
      include ExpressionOperators

      attr_reader :signal, :range

      def initialize(signal, range)
        @signal = signal
        @range = range
      end

      def to_verilog
        high, low = bounds
        rendered_high = high.respond_to?(:to_verilog) ? high.to_verilog : high.to_s
        rendered_low = low.respond_to?(:to_verilog) ? low.to_verilog : low.to_s
        "#{signal.to_verilog}[#{rendered_high}:#{rendered_low}]"
      end

      private

      def bounds
        if range.begin.is_a?(Integer) && range.end.is_a?(Integer)
          [[range.begin, range.end].max, [range.begin, range.end].min]
        else
          [range.begin, range.end]
        end
      end
    end
  end
end
