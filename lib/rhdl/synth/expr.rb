# frozen_string_literal: true

module RHDL
  module Synth
    # Base class for synthesis expressions
    class Expr
      attr_reader :width

      def initialize(width)
        @width = width
      end

      # Bitwise operators
      def &(other)
        BinaryOp.new(:&, self, wrap(other), result_width(other))
      end

      def |(other)
        BinaryOp.new(:|, self, wrap(other), result_width(other))
      end

      def ^(other)
        BinaryOp.new(:^, self, wrap(other), result_width(other))
      end

      def ~
        UnaryOp.new(:~, self, @width)
      end

      # Arithmetic operators
      def +(other)
        BinaryOp.new(:+, self, wrap(other), result_width(other) + 1)
      end

      def -(other)
        BinaryOp.new(:-, self, wrap(other), result_width(other))
      end

      def *(other)
        other_width = other.is_a?(Expr) ? other.width : bit_width(other)
        BinaryOp.new(:*, self, wrap(other), @width + other_width)
      end

      def /(other)
        BinaryOp.new(:/, self, wrap(other), @width)
      end

      def %(other)
        BinaryOp.new(:%, self, wrap(other), @width)
      end

      # Shift operators
      def <<(amount)
        BinaryOp.new(:<<, self, wrap(amount), @width)
      end

      def >>(amount)
        BinaryOp.new(:>>, self, wrap(amount), @width)
      end

      # Comparison operators (result is 1 bit)
      def ==(other)
        BinaryOp.new(:==, self, wrap(other), 1)
      end

      def !=(other)
        BinaryOp.new(:!=, self, wrap(other), 1)
      end

      def <(other)
        BinaryOp.new(:<, self, wrap(other), 1)
      end

      def >(other)
        BinaryOp.new(:>, self, wrap(other), 1)
      end

      def <=(other)
        # Use different symbol to avoid conflict with assignment
        BinaryOp.new(:le, self, wrap(other), 1)
      end

      def >=(other)
        BinaryOp.new(:>=, self, wrap(other), 1)
      end

      # Bit selection
      def [](index)
        if index.is_a?(Range)
          # Handle both ascending (0..7) and descending (7..0) ranges
          high = [index.begin, index.end].max
          low = [index.begin, index.end].min
          slice_width = high - low + 1
          Slice.new(self, index, slice_width)
        else
          BitSelect.new(self, index)
        end
      end

      # Concatenation
      def concat(*others)
        parts = [self] + others.map { |o| wrap(o) }
        total_width = parts.sum(&:width)
        Concat.new(parts, total_width)
      end

      # Replication
      def replicate(times)
        Replicate.new(self, times, @width * times)
      end

      protected

      def wrap(other)
        return other if other.is_a?(Expr)
        Literal.new(other, bit_width(other))
      end

      def result_width(other)
        other_width = other.is_a?(Expr) ? other.width : bit_width(other)
        [@width, other_width].max
      end

      def bit_width(value)
        return 1 if value == 0 || value == 1
        value.is_a?(Integer) ? [value.bit_length, 1].max : 1
      end
    end
  end
end
