# frozen_string_literal: true

module RHDL
  module DSL
    # Replication expression
    class Replication
      include ExpressionOperators

      attr_reader :signal, :times

      def initialize(signal, times)
        @signal = signal
        @times = times
      end

      def to_verilog
        rendered_times = times.respond_to?(:to_verilog) ? times.to_verilog : times.to_s
        "{#{rendered_times}{#{signal.to_verilog}}}"
      end
    end
  end
end
