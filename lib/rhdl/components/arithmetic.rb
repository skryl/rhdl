module RHDL
  module Components
    class HalfAdder < Component
      input :a
      input :b
      output :sum
      output :carry
    end

    class FullAdder < Component
      input :a
      input :b
      input :cin
      output :sum
      output :cout

      signal :s1
      signal :c1
      signal :c2
    end

    class RippleCarryAdder < Component
      def initialize(width = 8)
        @width = width
        input :a, width: width
        input :b, width: width
        input :cin
        output :sum, width: width
        output :cout

        # Internal signals for carry chain
        (@width - 1).times do |i|
          signal :"c#{i}"
        end
      end
    end

    class CarryLookAheadAdder < Component
      def initialize(width = 8)
        @width = width
        input :a, width: width
        input :b, width: width
        input :cin
        output :sum, width: width
        output :cout

        # Generate and propagate signals
        @width.times do |i|
          signal :"g#{i}"  # Generate
          signal :"p#{i}"  # Propagate
        end

        # Carry signals
        @width.times do |i|
          signal :"c#{i}"
        end
      end
    end

    class Multiplier < Component
      def initialize(width = 8)
        @width = width
        input :a, width: width
        input :b, width: width
        output :product, width: width * 2

        # Partial products
        @width.times do |i|
          @width.times do |j|
            signal :"pp#{i}_#{j}"
          end
        end

        # Internal sum and carry signals
        (@width - 1).times do |i|
          signal :"sum#{i}", width: width + 1
          signal :"carry#{i}", width: width + 1
        end
      end
    end

    class ALU < Component
      def initialize(width = 8)
        @width = width
        input :a, width: width
        input :b, width: width
        input :op_code, width: 4  # Operation selection
        input :cin               # Carry in for arithmetic operations
        output :result, width: width
        output :cout            # Carry out
        output :zero            # Zero flag
        output :negative        # Negative flag
        output :overflow        # Overflow flag

        # Internal signals
        signal :add_result, width: width
        signal :sub_result, width: width
        signal :and_result, width: width
        signal :or_result, width: width
        signal :xor_result, width: width
        signal :shl_result, width: width
        signal :shr_result, width: width
      end
    end
  end
end
