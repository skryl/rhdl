# frozen_string_literal: true

module RHDL
  module DSL
    # Bit selection expression
    class BitSelect
      attr_reader :signal, :index

      def initialize(signal, index)
        @signal = signal
        @index = index
      end

      def to_verilog
        "#{signal.to_verilog}[#{index}]"
      end
    end
  end
end
