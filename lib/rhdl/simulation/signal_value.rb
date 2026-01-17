# frozen_string_literal: true

module RHDL
  module HDL
    # Represents a signal value in the simulation
    # Supports multi-bit values and special states (X = unknown, Z = high-impedance)
    class SignalValue
      attr_reader :width, :value

      # Special values
      X = :unknown
      Z = :high_z

      def initialize(value, width: 1)
        @width = width
        @value = normalize(value)
      end

      def normalize(val)
        return val if val == X || val == Z
        val.is_a?(Integer) ? val & ((1 << @width) - 1) : val
      end

      def [](index)
        return X if @value == X
        return Z if @value == Z
        (@value >> index) & 1
      end

      def to_i
        @value.is_a?(Integer) ? @value : 0
      end

      def to_s
        return "X" * @width if @value == X
        return "Z" * @width if @value == Z
        @value.to_s(2).rjust(@width, '0')
      end

      def ==(other)
        other_val = other.is_a?(SignalValue) ? other.value : other
        @value == other_val
      end

      def zero?
        @value == 0
      end

      def high?
        @value != 0 && @value != X && @value != Z
      end
    end
  end
end
