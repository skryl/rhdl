# frozen_string_literal: true

module RHDL
  module HDL
    # Proxy for intermediate computed values in simulation behavior blocks
    # Allows operator chaining while tracking width
    class SimValueProxy
      attr_reader :width

      def initialize(value, width, context)
        @value = value
        @width = width
        @context = context
      end

      def value
        @value
      end

      # Bitwise operators
      def &(other)
        SimValueProxy.new(compute(:&, other), result_width(other), @context)
      end

      def |(other)
        SimValueProxy.new(compute(:|, other), result_width(other), @context)
      end

      def ^(other)
        SimValueProxy.new(compute(:^, other), result_width(other), @context)
      end

      def ~
        mask = (1 << @width) - 1
        SimValueProxy.new((~@value) & mask, @width, @context)
      end

      # Arithmetic operators
      def +(other)
        SimValueProxy.new(compute(:+, other), result_width(other) + 1, @context)
      end

      def -(other)
        SimValueProxy.new(compute(:-, other), result_width(other), @context)
      end

      def *(other)
        other_width = other.respond_to?(:width) ? other.width : 8
        SimValueProxy.new(compute(:*, other), @width + other_width, @context)
      end

      def /(other)
        other_val = resolve(other)
        result = other_val != 0 ? @value / other_val : 0
        SimValueProxy.new(result, @width, @context)
      end

      def %(other)
        other_val = resolve(other)
        result = other_val != 0 ? @value % other_val : 0
        SimValueProxy.new(result, @width, @context)
      end

      # Shift operators
      def <<(amount)
        mask = (1 << @width) - 1
        SimValueProxy.new((@value << resolve(amount)) & mask, @width, @context)
      end

      def >>(amount)
        SimValueProxy.new(@value >> resolve(amount), @width, @context)
      end

      # Comparison operators
      def ==(other)
        SimValueProxy.new((@value == resolve(other)) ? 1 : 0, 1, @context)
      end

      def !=(other)
        SimValueProxy.new((@value != resolve(other)) ? 1 : 0, 1, @context)
      end

      def <(other)
        SimValueProxy.new((@value < resolve(other)) ? 1 : 0, 1, @context)
      end

      def >(other)
        SimValueProxy.new((@value > resolve(other)) ? 1 : 0, 1, @context)
      end

      def <=(other)
        SimValueProxy.new((@value <= resolve(other)) ? 1 : 0, 1, @context)
      end

      def >=(other)
        SimValueProxy.new((@value >= resolve(other)) ? 1 : 0, 1, @context)
      end

      # Bit selection
      def [](index)
        if index.is_a?(Range)
          slice_width = index.max - index.min + 1
          mask = (1 << slice_width) - 1
          SimValueProxy.new((@value >> index.min) & mask, slice_width, @context)
        else
          SimValueProxy.new((@value >> index) & 1, 1, @context)
        end
      end

      def to_i
        @value
      end

      # Coercion support
      def coerce(other)
        [SimValueProxy.new(other, other == 0 ? 1 : other.bit_length, @context), self]
      end

      private

      def compute(op, other)
        other_val = resolve(other)
        result = @value.send(op, other_val)
        mask = (1 << @width) - 1
        result & mask
      end

      def result_width(other)
        other_width = other.respond_to?(:width) ? other.width : 8
        [@width, other_width].max
      end

      def resolve(other)
        case other
        when SimSignalProxy, SimOutputProxy, SimValueProxy
          other.value
        when Integer
          other
        else
          other.respond_to?(:value) ? other.value : other.to_i
        end
      end
    end
  end
end
