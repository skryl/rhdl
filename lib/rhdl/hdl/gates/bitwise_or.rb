# HDL Bitwise OR Gate
# Multi-bit OR operation

module RHDL
  module HDL
    class BitwiseOr < SimComponent
      parameter :width, default: 8

      input :a, width: :width
      input :b, width: :width
      output :y, width: :width

      behavior do
        y <= a | b
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end
    end
  end
end
