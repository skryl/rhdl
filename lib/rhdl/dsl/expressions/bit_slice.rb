# frozen_string_literal: true

module RHDL
  module DSL
    # Bit slice expression
    class BitSlice
      attr_reader :signal, :range

      def initialize(signal, range)
        @signal = signal
        @range = range
      end

      def to_vhdl
        "#{signal.to_vhdl}(#{range.max} downto #{range.min})"
      end

      def to_verilog
        "#{signal.to_verilog}[#{range.max}:#{range.min}]"
      end
    end
  end
end
