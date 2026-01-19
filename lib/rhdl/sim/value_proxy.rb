# frozen_string_literal: true

module RHDL
  module Sim
    # Proxy for intermediate computed values in simulation behavior blocks
    # Allows operator chaining while tracking width
    class ValueProxy
      attr_reader :width

      def initialize(value, width, context)
        @value = value
        @width = width
        @context = context
      end

      # Reinitialize for pooling - avoids allocation
      def reinitialize(value, width, context)
        @value = value
        @width = width
        @context = context
        self
      end

      def value
        @value
      end

      # Create a new proxy, using pool if available
      def self.create(value, width, context)
        if context.respond_to?(:proxy_pool) && (pool = context.proxy_pool)
          pool.acquire(value, width, context)
        else
          new(value, width, context)
        end
      end

      # Bitwise operators
      def &(other)
        width = result_width(other)
        ValueProxy.create(compute_masked(:&, other, width), width, @context)
      end

      def |(other)
        width = result_width(other)
        ValueProxy.create(compute_masked(:|, other, width), width, @context)
      end

      def ^(other)
        width = result_width(other)
        ValueProxy.create(compute_masked(:^, other, width), width, @context)
      end

      def ~
        ValueProxy.create((~@value) & MaskCache.mask(@width), @width, @context)
      end

      # Arithmetic operators
      def +(other)
        ValueProxy.create(compute(:+, other), result_width(other) + 1, @context)
      end

      def -(other)
        ValueProxy.create(compute(:-, other), result_width(other), @context)
      end

      def *(other)
        other_width = other.respond_to?(:width) ? other.width : 8
        ValueProxy.create(compute(:*, other), @width + other_width, @context)
      end

      def /(other)
        other_val = resolve(other)
        result = other_val != 0 ? @value / other_val : 0
        ValueProxy.create(result, @width, @context)
      end

      def %(other)
        other_val = resolve(other)
        result = other_val != 0 ? @value % other_val : 0
        ValueProxy.create(result, @width, @context)
      end

      # Shift operators
      def <<(amount)
        ValueProxy.create((@value << resolve(amount)) & MaskCache.mask(@width), @width, @context)
      end

      def >>(amount)
        ValueProxy.create(@value >> resolve(amount), @width, @context)
      end

      # Comparison operators
      def ==(other)
        ValueProxy.create((@value == resolve(other)) ? 1 : 0, 1, @context)
      end

      def !=(other)
        ValueProxy.create((@value != resolve(other)) ? 1 : 0, 1, @context)
      end

      def <(other)
        ValueProxy.create((@value < resolve(other)) ? 1 : 0, 1, @context)
      end

      def >(other)
        ValueProxy.create((@value > resolve(other)) ? 1 : 0, 1, @context)
      end

      def <=(other)
        ValueProxy.create((@value <= resolve(other)) ? 1 : 0, 1, @context)
      end

      def >=(other)
        ValueProxy.create((@value >= resolve(other)) ? 1 : 0, 1, @context)
      end

      # Bit selection
      def [](index)
        if index.is_a?(Range)
          # Handle both ascending (0..3) and descending (3..0) ranges
          # In HDL, bit slices are typically written high..low (e.g., 7..4)
          high = [index.begin, index.end].max
          low = [index.begin, index.end].min
          slice_width = high - low + 1
          ValueProxy.create((@value >> low) & MaskCache.mask(slice_width), slice_width, @context)
        else
          ValueProxy.create((@value >> index) & 1, 1, @context)
        end
      end

      # Concatenation
      def concat(*others)
        result = @value
        offset = @width
        total_width = @width
        others.each do |other|
          other_val = resolve(other)
          other_width = other.respond_to?(:width) ? other.width : (other_val == 0 ? 1 : other_val.bit_length)
          result = (other_val << offset) | result
          offset += other_width
          total_width += other_width
        end
        ValueProxy.create(result, total_width, @context)
      end

      # Replication
      def replicate(times)
        result = 0
        times.times do |i|
          result |= (@value << (i * @width))
        end
        ValueProxy.create(result, @width * times, @context)
      end

      def to_i
        @value
      end

      # Coercion support
      def coerce(other)
        [ValueProxy.create(other, other == 0 ? 1 : other.bit_length, @context), self]
      end

      private

      def compute(op, other)
        other_val = resolve(other)
        @value.send(op, other_val)
        # Don't mask here - let the caller specify the width for masking
      end

      def compute_masked(op, other, width)
        other_val = resolve(other)
        result = @value.send(op, other_val)
        result & MaskCache.mask(width)
      end

      def result_width(other)
        other_width = other.respond_to?(:width) ? other.width : 8
        [@width, other_width].max
      end

      def resolve(other)
        case other
        when SignalProxy, OutputProxy, ValueProxy
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
