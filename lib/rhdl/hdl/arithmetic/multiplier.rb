# HDL Multiplier
# Combinational multiplier (8x8 -> 16, synthesizable)

module RHDL
  module HDL
    class Multiplier < SimComponent
      parameter :width, default: 8
      parameter :product_width, default: 16

      input :a, width: :width
      input :b, width: :width
      output :product, width: :product_width

      behavior do
        product <= a * b
      end

      def initialize(name = nil, width: 8)
        @width = width
        @product_width = width * 2
        super(name)
      end
    end
  end
end
