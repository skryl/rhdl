# frozen_string_literal: true

module RHDL
  module DSL
    # Shared operator helpers for composable expression nodes.
    module ExpressionOperators
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

      def &(other)
        BinaryOp.new(:&, self, other)
      end

      def |(other)
        BinaryOp.new(:|, self, other)
      end

      def ^(other)
        BinaryOp.new(:^, self, other)
      end

      def <<(amount)
        BinaryOp.new(:<<, self, amount)
      end

      def >>(amount)
        BinaryOp.new(:>>, self, amount)
      end

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

      def ~
        UnaryOp.new(:~, self)
      end

      def !
        UnaryOp.new(:!, self)
      end

      def +@
        UnaryOp.new(:+, self)
      end

      def -@
        UnaryOp.new(:-, self)
      end

      def [](index)
        if index.is_a?(Range)
          BitSlice.new(self, index)
        else
          BitSelect.new(self, index)
        end
      end

      def concat(*others)
        Concatenation.new([self] + others)
      end

      def replicate(times)
        Replication.new(self, times)
      end
    end
  end
end

