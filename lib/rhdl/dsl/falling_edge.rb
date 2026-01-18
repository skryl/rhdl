# frozen_string_literal: true

module RHDL
  module DSL
    # Falling edge condition
    class FallingEdge
      attr_reader :signal

      def initialize(signal)
        @signal = signal
      end

      def to_verilog
        "negedge #{signal.respond_to?(:to_verilog) ? signal.to_verilog : signal}"
      end
    end
  end
end
