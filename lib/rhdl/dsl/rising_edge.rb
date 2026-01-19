# frozen_string_literal: true

module RHDL
  module DSL
    # Rising edge condition
    class RisingEdge
      attr_reader :signal

      def initialize(signal)
        @signal = signal
      end

      def to_verilog
        "posedge #{signal.respond_to?(:to_verilog) ? signal.to_verilog : signal}"
      end
    end
  end
end
