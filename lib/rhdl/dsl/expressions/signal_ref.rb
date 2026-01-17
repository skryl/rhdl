# frozen_string_literal: true

module RHDL
  module DSL
    # Signal value wrapper for DSL expressions
    class SignalRef
      attr_reader :name, :width, :component

      def initialize(name, width: 1, component: nil)
        @name = name
        @width = width
        @component = component
        @value = 0
      end

      # Bit selection
      def [](index)
        if index.is_a?(Range)
          BitSlice.new(self, index)
        else
          BitSelect.new(self, index)
        end
      end

      # Arithmetic operators
      def +(other)
        BinaryOp.new(:+, self, other)
      end

      def -(other)
        BinaryOp.new(:-, self, other)
      end

      def *(other)
        BinaryOp.new(:*, self, other)
      end

      def /(other)
        BinaryOp.new(:/, self, other)
      end

      def %(other)
        BinaryOp.new(:%, self, other)
      end

      # Bitwise operators
      def &(other)
        BinaryOp.new(:&, self, other)
      end

      def |(other)
        BinaryOp.new(:|, self, other)
      end

      def ^(other)
        BinaryOp.new(:^, self, other)
      end

      def ~
        UnaryOp.new(:~, self)
      end

      # Shift operators
      def <<(amount)
        BinaryOp.new(:<<, self, amount)
      end

      def >>(amount)
        BinaryOp.new(:>>, self, amount)
      end

      # Comparison operators
      def ==(other)
        BinaryOp.new(:==, self, other)
      end

      def !=(other)
        BinaryOp.new(:!=, self, other)
      end

      def <(other)
        BinaryOp.new(:<, self, other)
      end

      def >(other)
        BinaryOp.new(:>, self, other)
      end

      def <=(other)
        BinaryOp.new(:<=, self, other)
      end

      def >=(other)
        BinaryOp.new(:>=, self, other)
      end

      # Concatenation
      def concat(*others)
        Concatenation.new([self] + others)
      end

      # Replication
      def replicate(times)
        Replication.new(self, times)
      end

      def to_vhdl
        name.to_s
      end

      def to_verilog
        name.to_s
      end

      def to_s
        name.to_s
      end
    end
  end
end
