# frozen_string_literal: true

module RHDL
  module DSL
    # Concatenation expression
    class Concatenation
      attr_reader :signals

      def initialize(signals)
        @signals = signals
      end

      def to_vhdl
        parts = signals.map { |s| s.respond_to?(:to_vhdl) ? s.to_vhdl : s.to_s }
        "(#{parts.join(' & ')})"
      end

      def to_verilog
        parts = signals.map { |s| s.respond_to?(:to_verilog) ? s.to_verilog : s.to_s }
        "{#{parts.join(', ')}}"
      end
    end
  end
end
