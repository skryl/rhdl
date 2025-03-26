module RHDL
  module Components
    class Comparator < Component
      def initialize(width = 8)
        @width = width
        input :a, width: width
        input :b, width: width
        output :equal
        output :greater
        output :less

        # Internal signals for bit-by-bit comparison
        width.times do |i|
          signal :"eq#{i}"
          signal :"gt#{i}"
          signal :"lt#{i}"
        end
      end
    end

    class Equality < Component
      def initialize(width = 8)
        @width = width
        input :a, width: width
        input :b, width: width
        output :equal

        # Internal signals for bit-by-bit comparison
        width.times do |i|
          signal :"eq#{i}"
        end
      end
    end

    class ZeroDetector < Component
      def initialize(width = 8)
        @width = width
        input :data, width: width
        output :is_zero
      end
    end

    class SignDetector < Component
      def initialize(width = 8)
        @width = width
        input :data, width: width
        output :is_negative
        output :is_positive
        output :is_zero
      end
    end

    class MagnitudeComparator < Component
      def initialize(width = 8)
        @width = width
        input :a, width: width
        input :b, width: width
        output :a_gt_b
        output :a_eq_b
        output :a_lt_b

        # Internal signals
        width.times do |i|
          signal :"gt#{i}"
          signal :"eq#{i}"
          signal :"lt#{i}"
        end
      end
    end
  end
end
