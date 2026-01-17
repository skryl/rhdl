# frozen_string_literal: true

module RHDL
  module DSL
    # Replication expression
    class Replication
      attr_reader :signal, :times

      def initialize(signal, times)
        @signal = signal
        @times = times
      end

      def to_vhdl
        parts = Array.new(times) { signal.to_vhdl }
        "(#{parts.join(' & ')})"
      end

      def to_verilog
        "{#{times}{#{signal.to_verilog}}}"
      end
    end
  end
end
