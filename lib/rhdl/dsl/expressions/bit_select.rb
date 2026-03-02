# frozen_string_literal: true

module RHDL
  module DSL
    # Bit selection expression
    class BitSelect
      include ExpressionOperators

      attr_reader :signal, :index

      def initialize(signal, index)
        @signal = signal
        @index = index
      end

      def to_verilog
        rendered_index = index.respond_to?(:to_verilog) ? index.to_verilog : index.to_s
        "#{signal.to_verilog}[#{rendered_index}]"
      end
    end
  end
end
