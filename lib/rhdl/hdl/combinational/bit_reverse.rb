# HDL Combinational Logic Components
# Bit Reverser

module RHDL
  module HDL
    # Bit Reverser
    class BitReverse < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        output :y, width: @width
      end

      def propagate
        val = in_val(:a)
        result = 0
        @width.times do |i|
          result |= ((val >> i) & 1) << (@width - 1 - i)
        end
        out_set(:y, result)
      end
    end
  end
end
